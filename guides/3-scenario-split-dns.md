# Foundation Setup & Scenario 3: Split DNS

## Overview

## BIND Config

```bash


# DNS Server (VPC OP) Config

cat > /etc/named.conf << 'EOF'
options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { none; };
    directory "/var/named";
    allow-query { 10.0.0.0/8; };
    recursion yes;
    dnssec-validation no;
};

zone "op.viet.vn" IN {
    type master;
    file "/var/named/op.viet.vn.zone";
    allow-update { none; };
};

zone "2.10.in-addr.arpa" IN {
    type master;
    file "/var/named/10.2.rev";
    allow-update { none; };
};
EOF

cat > /var/named/op.viet.vn.zone << 'EOF'
$TTL 300
@   IN  SOA dns.op.viet.vn. admin.op.viet.vn. (
        2026080401 3600 1800 604800 300 )
@       IN  NS  dns.op.viet.vn.
dns     IN  A   10.2.1.10
app     IN  A   10.2.1.20
db      IN  A   10.2.1.30
EOF

cat > /var/named/10.2.rev << 'EOF'
$TTL 300
@   IN  SOA dns.op.viet.vn. admin.op.viet.vn. (
        2026080401 3600 1800 604800 300 )
@   IN  NS  dns.op.viet.vn.
10  IN  PTR dns.op.viet.vn.
20  IN  PTR app.op.viet.vn.
30  IN  PTR db.op.viet.vn.
EOF

chown named:named /var/named/op.viet.vn.zone /var/named/10.2.rev
systemctl start named
```

---

## Split DNS (Long Term pattern)

Each environment is authoritative for its own domain. Cross-domain queries are forwarded via Route 53 Resolver endpoints.

```
EC2-Cloud queries app.cloud.viet.vn
  → VPC DNS (10.1.0.2)
  → Route 53 PHZ: cloud.viet.vn
  → Returns 10.1.0.40  ✓ (never leaves VPC A)

EC2-Cloud queries app.op.viet.vn
  → VPC DNS (10.1.0.2)
  → Resolver Rule: op.viet.vn → Outbound Endpoint
  → VPC Peering → BIND (10.2.1.10)
  → Returns 10.2.1.20  ✓

App Server queries app.cloud.viet.vn
  → DHCP → BIND (10.2.1.10)
  → Forwarder: cloud.viet.vn → Inbound Endpoint (10.1.1.10)
  → VPC Peering → Route 53 PHZ
  → Returns 10.1.0.40  ✓

App Server queries app.op.viet.vn
  → BIND (10.2.1.10)
  → Authoritative zone op.viet.vn
  → Returns 10.2.1.20  ✓ (never leaves VPC OP)
```

## Step 1 — Route 53 Private Hosted Zone for cloud.viet.vn

```bash
# Create PHZ and associate with VPC A
PHZ_CLOUD=$(aws route53 create-hosted-zone \
  --name cloud.viet.vn \
  --vpc VPCRegion=ap-southeast-1,VPCId=$VPC_A_ID \
  --caller-reference "demo-viet-vn-$(date +%s)" \
  --hosted-zone-config Comment="Cloud private zone",PrivateZone=true \
  --query 'HostedZone.Id' --output text)

# Add records for cloud resources
cat > /tmp/cloud-records.json << EOF
{
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "app.cloud.viet.vn",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "10.1.0.40"}]
      }
    },
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "db.cloud.viet.vn",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "10.1.0.50"}]
      }
    },
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "api.cloud.viet.vn",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "app.cloud.viet.vn"}]
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id $PHZ_CLOUD \
  --change-batch file:///tmp/cloud-records.json

echo "PHZ cloud.viet.vn: $PHZ_CLOUD"
```


## Step 2 — Create Inbound Resolver Endpoint

Receives DNS queries from on-premises (BIND forwards to these IPs).

```bash
INBOUND_EP=$(aws route53resolver create-resolver-endpoint \
  --creator-request-id "inbound-$(date +%s)" \
  --name "Inbound-VPC-A" \
  --security-group-ids sg-resolver-xxx \
  --direction INBOUND \
  --ip-addresses \
    SubnetId=$SUBNET_A,Ip=10.1.1.10 \
    SubnetId=$SUBNET_A2,Ip=10.1.2.10 \
  --region ap-southeast-1 \
  --query 'ResolverEndpoint.Id' --output text)

echo "Inbound Endpoint: $INBOUND_EP"
# Wait ~2 min for status to become OPERATIONAL
aws route53resolver get-resolver-endpoint \
  --resolver-endpoint-id $INBOUND_EP \
  --region ap-southeast-1 \
  --query 'ResolverEndpoint.Status'
```

## Step 3 — Create Outbound Resolver Endpoint

Sends DNS queries from VPC A to on-premises BIND.

```bash
OUTBOUND_EP=$(aws route53resolver create-resolver-endpoint \
  --creator-request-id "outbound-$(date +%s)" \
  --name "Outbound-VPC-A" \
  --security-group-ids sg-resolver-yyy \
  --direction OUTBOUND \
  --ip-addresses \
    SubnetId=$SUBNET_A,Ip=10.1.1.11 \
    SubnetId=$SUBNET_A2,Ip=10.1.2.11 \
  --region ap-southeast-1 \
  --query 'ResolverEndpoint.Id' --output text)

echo "Outbound Endpoint: $OUTBOUND_EP"
aws route53resolver get-resolver-endpoint \
  --resolver-endpoint-id $OUTBOUND_EP \
  --region ap-southeast-1 \
  --query 'ResolverEndpoint.Status'
```

## Step 4 — Create Resolver Rule for op.viet.vn

Tells VPC A: "for `op.viet.vn`, send queries to BIND via the Outbound Endpoint."

```bash
RULE_ID=$(aws route53resolver create-resolver-rule \
  --creator-request-id "rule-corp-local-$(date +%s)" \
  --name "Forward-corp-local-to-BIND" \
  --rule-type FORWARD \
  --domain-name op.viet.vn \
  --resolver-endpoint-id $OUTBOUND_EP \
  --target-ips Ip=10.2.1.10,Port=53 \
  --region ap-southeast-1 \
  --query 'ResolverRule.Id' --output text)

# Associate the rule with VPC A
aws route53resolver associate-resolver-rule \
  --resolver-rule-id $RULE_ID \
  --vpc-id $VPC_A_ID \
  --region ap-southeast-1

echo "Resolver Rule: $RULE_ID"
```

## Step 5 — Configure BIND to Forward cloud.viet.vn to Inbound Endpoint

SSH to the DNS Server (`10.2.1.10`) and update `/etc/named.conf`:

```bash
# Run on DNS Server (10.2.1.10)
sudo tee /etc/named.conf > /dev/null << 'EOF'
options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { none; };
    directory "/var/named";
    allow-query { 10.0.0.0/8; };
    recursion yes;
    dnssec-validation no;
};

# On-prem domain: BIND is authoritative
zone "op.viet.vn" IN {
    type master;
    file "/var/named/op.viet.vn.zone";
    allow-update { none; };
};

zone "2.10.in-addr.arpa" IN {
    type master;
    file "/var/named/10.2.rev";
    allow-update { none; };
};

# Cloud domain: forward to Route 53 Inbound Endpoint
zone "cloud.viet.vn" IN {
    type forward;
    forward only;
    forwarders { 10.1.1.10; 10.1.2.10; };
};
EOF

sudo systemctl restart named
sudo systemctl status named
```

## Demo Verification

```bash
# ── From EC2-Cloud (10.1.0.40) ───────────────────────────────────

# Cloud → Cloud: resolves directly via VPC DNS, no BIND involved
dig app.cloud.viet.vn
# Expected: 10.1.0.40

# CNAME record
dig api.cloud.viet.vn
# Expected: CNAME → app.cloud.viet.vn → 10.1.0.40

# Cloud → On-prem: goes via Outbound Endpoint → BIND
dig app.op.viet.vn
# Expected: 10.2.1.20

dig db.op.viet.vn
# Expected: 10.2.1.30

# AWS services still resolve correctly
dig s3.ap-southeast-1.amazonaws.com
# Expected: AWS-managed IPs

# ── From App Server (10.2.1.20) ──────────────────────────────────

# On-prem → On-prem: resolves directly in BIND, no AWS hop
dig @10.2.1.10 app.op.viet.vn
# Expected: 10.2.1.20

# On-prem → Cloud: BIND forwards to Inbound Endpoint
dig @10.2.1.10 app.cloud.viet.vn
# Expected: 10.1.0.40
```


**Notes:** In Split DNS, an on-prem DNS failure only affects `op.viet.vn` resolution. Cloud resources keep working. Compare to Scenario 2 (All On-Prem) where BIND failure takes down both environments.

The endpoints are the dominant cost. For dev/test, drop to 1 IP per endpoint (single AZ) to cut $182.50/month.

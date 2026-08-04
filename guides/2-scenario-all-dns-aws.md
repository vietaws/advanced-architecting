# Scenario 2: All DNS on AWS

## Concept

Route 53 is the single DNS authority for **both** environments. It hosts private hosted zones for both `cloud.corp.local` (cloud resources) and `corp.local` (on-premises resources). BIND on-premises becomes a pure forwarder — it forwards every query to the Route 53 Inbound Resolver Endpoint and has no authoritative zones of its own.

```
EC2-Cloud queries app.cloud.corp.local
  → VPC DNS (10.1.0.2)
  → Route 53 PHZ: cloud.corp.local
  → Returns 10.1.1.50  ✓  (instant, never leaves VPC A)

EC2-Cloud queries app.corp.local
  → VPC DNS (10.1.0.2)
  → Route 53 PHZ: corp.local (hosted in AWS)
  → Returns 10.2.1.20  ✓

App Server queries app.cloud.corp.local
  → BIND (10.2.1.10) — forwarder only
  → Inbound Endpoint (10.1.1.10)
  → Route 53 PHZ: cloud.corp.local
  → Returns 10.1.1.50  ✓

App Server queries app.corp.local
  → BIND (10.2.1.10) — forwarder only
  → Inbound Endpoint (10.1.1.10)
  → Route 53 PHZ: corp.local
  → Returns 10.2.1.20  ✓
```

**No Outbound Resolver needed** — queries never need to travel from AWS back to BIND.

**Prerequisite:** Foundation infrastructure from `3-scenario-split-dns.md` (Part 1) is deployed.

---

## Step 1 — Create Route 53 PHZ for cloud.corp.local

```bash
PHZ_CLOUD=$(aws route53 create-hosted-zone \
  --name cloud.corp.local \
  --vpc VPCRegion=ap-southeast-1,VPCId=$VPC_A_ID \
  --caller-reference "demo-viet-vn-$(date +%s)" \
  --hosted-zone-config Comment="Cloud resources",PrivateZone=true \
  --query 'HostedZone.Id' --output text)

# Also associate with VPC OP so on-prem EC2s can resolve it directly
# (needed when BIND is the forwarder — queries arrive at inbound endpoint inside VPC A,
#  which already has access; but associating VPC OP is good practice)
aws route53 associate-vpc-with-hosted-zone \
  --hosted-zone-id $PHZ_CLOUD \
  --vpc VPCRegion=ap-southeast-1,VPCId=$VPC_OP_ID

# Add records
cat > /tmp/cloud-records.json << EOF
{
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "app.cloud.corp.local",
        "Type": "A", "TTL": 300,
        "ResourceRecords": [{"Value": "10.1.1.50"}]
      }
    },
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "web.cloud.corp.local",
        "Type": "A", "TTL": 300,
        "ResourceRecords": [{"Value": "10.1.1.51"}]
      }
    },
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "api.cloud.corp.local",
        "Type": "CNAME", "TTL": 300,
        "ResourceRecords": [{"Value": "app.cloud.corp.local"}]
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id $PHZ_CLOUD \
  --change-batch file:///tmp/cloud-records.json

echo "PHZ cloud.corp.local: $PHZ_CLOUD"
```

---

## Step 2 — Create Route 53 PHZ for corp.local

Route 53 now hosts on-premises records. Records must be updated manually when on-prem IPs change (or automated via Lambda/EventBridge).

```bash
PHZ_ONPREM=$(aws route53 create-hosted-zone \
  --name corp.local \
  --vpc VPCRegion=ap-southeast-1,VPCId=$VPC_A_ID \
  --caller-reference "corp-local-$(date +%s)" \
  --hosted-zone-config Comment="On-prem resources managed in Route 53",PrivateZone=true \
  --query 'HostedZone.Id' --output text)

aws route53 associate-vpc-with-hosted-zone \
  --hosted-zone-id $PHZ_ONPREM \
  --vpc VPCRegion=ap-southeast-1,VPCId=$VPC_OP_ID

cat > /tmp/onprem-records.json << EOF
{
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "dns.corp.local",
        "Type": "A", "TTL": 300,
        "ResourceRecords": [{"Value": "10.2.1.10"}]
      }
    },
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "app.corp.local",
        "Type": "A", "TTL": 300,
        "ResourceRecords": [{"Value": "10.2.1.20"}]
      }
    },
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "db.corp.local",
        "Type": "A", "TTL": 300,
        "ResourceRecords": [{"Value": "10.2.1.30"}]
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id $PHZ_ONPREM \
  --change-batch file:///tmp/onprem-records.json

echo "PHZ corp.local: $PHZ_ONPREM"
```

---

## Step 3 — Create Resolver Endpoint Security Group

```bash
SG_RESOLVER=$(aws ec2 create-security-group \
  --group-name sg-resolver-inbound \
  --description "Route 53 Inbound Resolver" \
  --vpc-id $VPC_A_ID --region ap-southeast-1 \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_RESOLVER \
  --protocol udp --port 53 --cidr 10.0.0.0/8 --region ap-southeast-1
aws ec2 authorize-security-group-ingress --group-id $SG_RESOLVER \
  --protocol tcp --port 53 --cidr 10.0.0.0/8 --region ap-southeast-1
```

---

## Step 4 — Create Inbound Resolver Endpoint

Receives DNS queries forwarded from on-premises BIND.

```bash
INBOUND_EP=$(aws route53resolver create-resolver-endpoint \
  --creator-request-id "inbound-$(date +%s)" \
  --name "Inbound-VPC-A" \
  --security-group-ids $SG_RESOLVER \
  --direction INBOUND \
  --ip-addresses \
    SubnetId=$SUBNET_A,Ip=10.1.1.10 \
    SubnetId=$SUBNET_A2,Ip=10.1.2.10 \
  --region ap-southeast-1 \
  --query 'ResolverEndpoint.Id' --output text)

echo "Inbound Endpoint: $INBOUND_EP"

# Wait for OPERATIONAL status (~2 min)
watch -n 10 "aws route53resolver get-resolver-endpoint \
  --resolver-endpoint-id $INBOUND_EP \
  --region ap-southeast-1 \
  --query 'ResolverEndpoint.Status' --output text"
```

---

## Step 5 — Reconfigure BIND as Pure Forwarder

SSH to the DNS Server (`10.2.1.10`). Remove all authoritative zones. Forward everything to the Inbound Endpoint.

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

    # Forward ALL queries to Route 53 Inbound Endpoint (HA pair)
    forwarders {
        10.1.1.10;
        10.1.2.10;
    };
    forward only;
};

logging {
    channel query_log {
        file "/var/log/named/query.log" versions 3 size 10m;
        severity info;
        print-time yes;
    };
    category queries { query_log; };
};
EOF

sudo mkdir -p /var/log/named
sudo chown named:named /var/log/named
sudo systemctl restart named

# Verify BIND is forwarding
sudo tail -f /var/log/named/query.log
```

---

## Step 6 — Enable Resolver Query Logging

This is a key demo moment — show every DNS query in CloudWatch Logs in real time.

```bash
# Create CloudWatch log group
aws logs create-log-group \
  --log-group-name /aws/route53/resolver-queries \
  --region ap-southeast-1

LOG_GROUP_ARN=$(aws logs describe-log-groups \
  --log-group-name-prefix /aws/route53/resolver-queries \
  --region ap-southeast-1 \
  --query 'logGroups[0].arn' --output text)

# Create query log config
QLOG_ID=$(aws route53resolver create-resolver-query-log-config \
  --name "HybridDNS-QueryLog" \
  --destination-arn $LOG_GROUP_ARN \
  --region ap-southeast-1 \
  --query 'ResolverQueryLogConfig.Id' --output text)

# Associate with VPC A
aws route53resolver associate-resolver-query-log-config \
  --resolver-query-log-config-id $QLOG_ID \
  --resource-id $VPC_A_ID \
  --region ap-southeast-1

echo "Query Log Config: $QLOG_ID"
```

---

## Demo Verification

```bash
# ── From EC2-Cloud (10.1.1.50) ───────────────────────────────────

# Cloud → Cloud: VPC DNS answers directly, no BIND involved
dig app.cloud.corp.local
# Expected: 10.1.1.50

# CNAME chain
dig api.cloud.corp.local
# Expected: CNAME → app.cloud.corp.local → 10.1.1.50

# Cloud → On-prem: Route 53 PHZ answers (no Outbound Endpoint needed)
dig app.corp.local
# Expected: 10.2.1.20

dig db.corp.local
# Expected: 10.2.1.30

# AWS services resolve normally
dig s3.ap-southeast-1.amazonaws.com
# Expected: AWS-managed IPs


# ── From App Server (10.2.1.20) ──────────────────────────────────

# On-prem → Cloud: BIND forwards to Inbound Endpoint → PHZ
dig @10.2.1.10 app.cloud.corp.local
# Expected: 10.1.1.50

# On-prem → On-prem: BIND forwards to Inbound Endpoint → PHZ corp.local
dig @10.2.1.10 app.corp.local
# Expected: 10.2.1.20


# ── CloudWatch Logs (show live) ──────────────────────────────────
# After running the digs above, open CloudWatch Logs:
# Log group: /aws/route53/resolver-queries
# Filter: { $.queryName = "app.cloud.corp.local." }
# Show: srcAddr (on-prem IP), queryName, resolverEndpointId
```

## Blast Radius Test

```bash
# Stop BIND
sudo systemctl stop named   # on DNS Server

# From EC2-Cloud: both domains still resolve (Route 53 PHZ handles everything)
dig app.cloud.corp.local     # ✓ still works
dig app.corp.local       # ✓ still works

# From App Server: BIND is down — on-prem queries fail
dig app.cloud.corp.local     # ✗ times out (BIND was the forwarder)
dig app.corp.local       # ✗ times out

# Restart BIND → recovery
sudo systemctl start named
```

**Talking point:** Route 53 is resilient and fully managed. But on-premises machines that depend on BIND as their DNS server lose resolution when BIND goes down. The solution is a secondary BIND or pointing VPC OP DHCP directly to the Inbound Endpoint IPs.

---

## Cost (All DNS on AWS)

| Component | IPs / Count | Monthly |
|-----------|------------|---------|
| Inbound Resolver Endpoint | 2 IPs (HA) | $182.50 |
| PHZ `cloud.corp.local` | 1 zone | $0.50 |
| PHZ `corp.local` | 1 zone | $0.50 |
| DNS queries (est. 1M) | — | $0.40 |
| **Total (Route 53)** | | **~$183.90/month** |

No Outbound Endpoint, no Resolver Rules — the lowest Route 53 Resolver cost of the three scenarios.

The trade-off: on-premises records must be manually maintained in Route 53 (or automated). Any IP change on-prem requires a Route 53 record update.

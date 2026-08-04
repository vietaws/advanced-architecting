# Foundation Setup & Scenario 3: Split DNS

## Overview

This guide covers two parts of the demo:

- **Part 1:** Deploy the base infrastructure that all three scenarios share.
- **Part 2:** Build Scenario 3 (Split DNS) — the recommended long-term hybrid pattern.

---

# PART 1 — Foundation Setup

Deploy this once. Every subsequent scenario modifies this base without rebuilding it.

## Architecture

```
VPC A (10.1.0.0/16)                    VPC OP (10.2.0.0/16)
───────────────────                    ────────────────────
Subnet A   10.1.1.0/24                 Subnet OP  10.2.1.0/24
Subnet A2  10.1.2.0/24 (HA)
                                         DNS Server  10.2.1.10
EC2-Cloud  10.1.1.50                     App Server  10.2.1.20
S3 Gateway Endpoint
                   ←──── VPC Peering ────→
```

## Step 1 — Create VPC A

```bash
VPC_A_ID=$(aws ec2 create-vpc \
  --cidr-block 10.1.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=VPC-A-Cloud}]' \
  --region ap-southeast-1 \
  --query 'Vpc.VpcId' --output text)

aws ec2 modify-vpc-attribute --vpc-id $VPC_A_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_A_ID --enable-dns-support

echo "VPC A: $VPC_A_ID"
```

## Step 2 — Create Subnets in VPC A

```bash
# Primary subnet (AZ-a) — EC2 and Resolver IPs
SUBNET_A=$(aws ec2 create-subnet \
  --vpc-id $VPC_A_ID \
  --cidr-block 10.1.1.0/24 \
  --availability-zone ap-southeast-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=VPC-A-Private-1a}]' \
  --region ap-southeast-1 \
  --query 'Subnet.SubnetId' --output text)

# Secondary subnet (AZ-b) — Resolver HA only
SUBNET_A2=$(aws ec2 create-subnet \
  --vpc-id $VPC_A_ID \
  --cidr-block 10.1.2.0/24 \
  --availability-zone ap-southeast-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=VPC-A-Private-1b}]' \
  --region ap-southeast-1 \
  --query 'Subnet.SubnetId' --output text)

echo "Subnet A (1a): $SUBNET_A"
echo "Subnet A2 (1b): $SUBNET_A2"
```

## Step 3 — Create VPC OP

```bash
VPC_OP_ID=$(aws ec2 create-vpc \
  --cidr-block 10.2.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=VPC-OP-OnPrem}]' \
  --region ap-southeast-1 \
  --query 'Vpc.VpcId' --output text)

aws ec2 modify-vpc-attribute --vpc-id $VPC_OP_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_OP_ID --enable-dns-support

SUBNET_OP=$(aws ec2 create-subnet \
  --vpc-id $VPC_OP_ID \
  --cidr-block 10.2.1.0/24 \
  --availability-zone ap-southeast-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=VPC-OP-Private}]' \
  --region ap-southeast-1 \
  --query 'Subnet.SubnetId' --output text)

echo "VPC OP: $VPC_OP_ID"
echo "Subnet OP: $SUBNET_OP"
```

## Step 4 — VPC Peering

```bash
PEERING_ID=$(aws ec2 create-vpc-peering-connection \
  --vpc-id $VPC_A_ID \
  --peer-vpc-id $VPC_OP_ID \
  --tag-specifications 'ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=VPC-A-to-VPC-OP}]' \
  --region ap-southeast-1 \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' --output text)

aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id $PEERING_ID \
  --region ap-southeast-1

# Get route table IDs
RT_A=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_A_ID" \
  --region ap-southeast-1 \
  --query 'RouteTables[0].RouteTableId' --output text)

RT_OP=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_OP_ID" \
  --region ap-southeast-1 \
  --query 'RouteTables[0].RouteTableId' --output text)

# Add routes
aws ec2 create-route --route-table-id $RT_A \
  --destination-cidr-block 10.2.0.0/16 \
  --vpc-peering-connection-id $PEERING_ID --region ap-southeast-1

aws ec2 create-route --route-table-id $RT_OP \
  --destination-cidr-block 10.1.0.0/16 \
  --vpc-peering-connection-id $PEERING_ID --region ap-southeast-1

echo "Peering: $PEERING_ID"
```

## Step 5 — Security Groups

```bash
# VPC A — EC2
SG_A=$(aws ec2 create-security-group \
  --group-name sg-vpc-a-ec2 \
  --description "VPC A EC2" \
  --vpc-id $VPC_A_ID --region ap-southeast-1 \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_A \
  --protocol tcp --port 22 --cidr 10.2.0.0/16 --region ap-southeast-1
aws ec2 authorize-security-group-ingress --group-id $SG_A \
  --protocol icmp --port -1 --cidr 10.2.0.0/16 --region ap-southeast-1

# VPC OP — DNS Server
SG_DNS=$(aws ec2 create-security-group \
  --group-name sg-dns-server \
  --description "On-prem BIND DNS" \
  --vpc-id $VPC_OP_ID --region ap-southeast-1 \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_DNS \
  --protocol udp --port 53 --cidr 10.0.0.0/8 --region ap-southeast-1
aws ec2 authorize-security-group-ingress --group-id $SG_DNS \
  --protocol tcp --port 53 --cidr 10.0.0.0/8 --region ap-southeast-1
aws ec2 authorize-security-group-ingress --group-id $SG_DNS \
  --protocol tcp --port 22 --cidr 10.2.0.0/16 --region ap-southeast-1

# VPC OP — App Server
SG_APP=$(aws ec2 create-security-group \
  --group-name sg-app-server \
  --description "On-prem App Server" \
  --vpc-id $VPC_OP_ID --region ap-southeast-1 \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_APP \
  --protocol tcp --port 22 --cidr 10.0.0.0/8 --region ap-southeast-1
aws ec2 authorize-security-group-ingress --group-id $SG_APP \
  --protocol icmp --port -1 --cidr 10.0.0.0/8 --region ap-southeast-1
```

## Step 6 — Launch EC2 Instances

```bash
# Replace with your key pair name and latest AL2023 AMI for ap-southeast-1
KEY_PAIR="your-key-pair"
AMI_ID="ami-0c802847a501da9d4"   # Amazon Linux 2023, ap-southeast-1 — verify before use

# EC2-Cloud (VPC A)
aws ec2 run-instances \
  --image-id $AMI_ID --instance-type t3.micro \
  --subnet-id $SUBNET_A \
  --security-group-ids $SG_A \
  --key-name $KEY_PAIR \
  --private-ip-address 10.1.1.50 \
  --no-associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=EC2-Cloud}]' \
  --region ap-southeast-1

# DNS Server (VPC OP) — user-data installs BIND
cat > /tmp/bind-userdata.sh << 'USERDATA'
#!/bin/bash
dnf install -y bind bind-utils
systemctl enable named

cat > /etc/named.conf << 'EOF'
options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { none; };
    directory "/var/named";
    allow-query { 10.0.0.0/8; };
    recursion yes;
    dnssec-validation no;
};

zone "corp.local" IN {
    type master;
    file "/var/named/corp.local.zone";
    allow-update { none; };
};

zone "2.10.in-addr.arpa" IN {
    type master;
    file "/var/named/10.2.rev";
    allow-update { none; };
};
EOF

cat > /var/named/corp.local.zone << 'EOF'
$TTL 300
@   IN  SOA dns.corp.local. admin.corp.local. (
        2026080401 3600 1800 604800 300 )
@       IN  NS  dns.corp.local.
dns     IN  A   10.2.1.10
app     IN  A   10.2.1.20
db      IN  A   10.2.1.30
EOF

cat > /var/named/10.2.rev << 'EOF'
$TTL 300
@   IN  SOA dns.corp.local. admin.corp.local. (
        2026080401 3600 1800 604800 300 )
@   IN  NS  dns.corp.local.
10  IN  PTR dns.corp.local.
20  IN  PTR app.corp.local.
30  IN  PTR db.corp.local.
EOF

chown named:named /var/named/corp.local.zone /var/named/10.2.rev
systemctl start named
USERDATA

aws ec2 run-instances \
  --image-id $AMI_ID --instance-type t3.micro \
  --subnet-id $SUBNET_OP \
  --security-group-ids $SG_DNS \
  --key-name $KEY_PAIR \
  --private-ip-address 10.2.1.10 \
  --no-associate-public-ip-address \
  --user-data file:///tmp/bind-userdata.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=DNS-Server}]' \
  --region ap-southeast-1

# App Server (VPC OP)
aws ec2 run-instances \
  --image-id $AMI_ID --instance-type t3.micro \
  --subnet-id $SUBNET_OP \
  --security-group-ids $SG_APP \
  --key-name $KEY_PAIR \
  --private-ip-address 10.2.1.20 \
  --no-associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=App-Server}]' \
  --region ap-southeast-1
```

## Step 7 — S3 Bucket + Gateway Endpoint

```bash
BUCKET="hybrid-dns-demo-$(date +%s)"
aws s3api create-bucket \
  --bucket $BUCKET \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1

aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_A_ID \
  --service-name com.amazonaws.ap-southeast-1.s3 \
  --route-table-ids $RT_A \
  --region ap-southeast-1 \
  --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=S3-GW-Endpoint}]'

echo "S3 Bucket: $BUCKET"
```

## End-State Verification

```bash
# IP connectivity works both ways
ping -c3 10.2.1.20   # from EC2-Cloud → App Server
ping -c3 10.1.1.50   # from App Server → EC2-Cloud

# DNS is NOT yet cross-environment (expected at this stage)
dig app.cloud.corp.local   # NXDOMAIN — not configured yet
dig app.corp.local     # NXDOMAIN from EC2-Cloud — expected

# BIND is running on DNS Server
dig @10.2.1.10 app.corp.local   # should return 10.2.1.20
dig @10.2.1.10 db.corp.local    # should return 10.2.1.30

# S3 reachable from EC2-Cloud
aws s3 ls s3://$BUCKET --region ap-southeast-1
```

---

# PART 2 — Scenario 3: Split DNS (Recommended Long-Term Pattern)

## Concept

Each environment is authoritative for its own domain. Cross-domain queries are forwarded via Route 53 Resolver endpoints.

```
EC2-Cloud queries app.cloud.corp.local
  → VPC DNS (10.1.0.2)
  → Route 53 PHZ: cloud.corp.local
  → Returns 10.1.1.50  ✓ (never leaves VPC A)

EC2-Cloud queries app.corp.local
  → VPC DNS (10.1.0.2)
  → Resolver Rule: corp.local → Outbound Endpoint
  → VPC Peering → BIND (10.2.1.10)
  → Returns 10.2.1.20  ✓

App Server queries app.cloud.corp.local
  → DHCP → BIND (10.2.1.10)
  → Forwarder: cloud.corp.local → Inbound Endpoint (10.1.1.10)
  → VPC Peering → Route 53 PHZ
  → Returns 10.1.1.50  ✓

App Server queries app.corp.local
  → BIND (10.2.1.10)
  → Authoritative zone corp.local
  → Returns 10.2.1.20  ✓ (never leaves VPC OP)
```

**Prerequisite:** Complete Part 1 and have the Route 53 Inbound Endpoint already deployed (IPs `10.1.1.10` and `10.1.2.10`). If running this scenario standalone, create the inbound endpoint first — see `2-scenario-all-dns-aws.md` Step 1.

## Step 1 — Route 53 Private Hosted Zone for cloud.corp.local

```bash
# Create PHZ and associate with VPC A
PHZ_CLOUD=$(aws route53 create-hosted-zone \
  --name cloud.corp.local \
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
        "Name": "app.cloud.corp.local",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "10.1.1.50"}]
      }
    },
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "web.cloud.corp.local",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "10.1.1.51"}]
      }
    },
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "api.cloud.corp.local",
        "Type": "CNAME",
        "TTL": 300,
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

## Step 2 — Create Resolver Endpoints Security Group

```bash
SG_RESOLVER=$(aws ec2 create-security-group \
  --group-name sg-resolver-endpoints \
  --description "Route 53 Resolver Endpoints" \
  --vpc-id $VPC_A_ID --region ap-southeast-1 \
  --query 'GroupId' --output text)

# Allow DNS from both VPCs
aws ec2 authorize-security-group-ingress --group-id $SG_RESOLVER \
  --protocol udp --port 53 --cidr 10.0.0.0/8 --region ap-southeast-1
aws ec2 authorize-security-group-ingress --group-id $SG_RESOLVER \
  --protocol tcp --port 53 --cidr 10.0.0.0/8 --region ap-southeast-1
```

## Step 3 — Create Inbound Resolver Endpoint

Receives DNS queries from on-premises (BIND forwards to these IPs).

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
# Wait ~2 min for status to become OPERATIONAL
aws route53resolver get-resolver-endpoint \
  --resolver-endpoint-id $INBOUND_EP \
  --region ap-southeast-1 \
  --query 'ResolverEndpoint.Status'
```

## Step 4 — Create Outbound Resolver Endpoint

Sends DNS queries from VPC A to on-premises BIND.

```bash
OUTBOUND_EP=$(aws route53resolver create-resolver-endpoint \
  --creator-request-id "outbound-$(date +%s)" \
  --name "Outbound-VPC-A" \
  --security-group-ids $SG_RESOLVER \
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

## Step 5 — Create Resolver Rule for corp.local

Tells VPC A: "for `corp.local`, send queries to BIND via the Outbound Endpoint."

```bash
RULE_ID=$(aws route53resolver create-resolver-rule \
  --creator-request-id "rule-corp-local-$(date +%s)" \
  --name "Forward-corp-local-to-BIND" \
  --rule-type FORWARD \
  --domain-name corp.local \
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

## Step 6 — Configure BIND to Forward cloud.corp.local to Inbound Endpoint

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
zone "corp.local" IN {
    type master;
    file "/var/named/corp.local.zone";
    allow-update { none; };
};

zone "2.10.in-addr.arpa" IN {
    type master;
    file "/var/named/10.2.rev";
    allow-update { none; };
};

# Cloud domain: forward to Route 53 Inbound Endpoint
zone "cloud.corp.local" IN {
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
# ── From EC2-Cloud (10.1.1.50) ───────────────────────────────────

# Cloud → Cloud: resolves directly via VPC DNS, no BIND involved
dig app.cloud.corp.local
# Expected: 10.1.1.50

# CNAME record
dig api.cloud.corp.local
# Expected: CNAME → app.cloud.corp.local → 10.1.1.50

# Cloud → On-prem: goes via Outbound Endpoint → BIND
dig app.corp.local
# Expected: 10.2.1.20

dig db.corp.local
# Expected: 10.2.1.30

# AWS services still resolve correctly
dig s3.ap-southeast-1.amazonaws.com
# Expected: AWS-managed IPs

# ── From App Server (10.2.1.20) ──────────────────────────────────

# On-prem → On-prem: resolves directly in BIND, no AWS hop
dig @10.2.1.10 app.corp.local
# Expected: 10.2.1.20

# On-prem → Cloud: BIND forwards to Inbound Endpoint
dig @10.2.1.10 app.cloud.corp.local
# Expected: 10.1.1.50
```

## Blast Radius Test (Key Demo Moment)

```bash
# 1. Stop BIND on DNS Server
sudo systemctl stop named

# 2. From EC2-Cloud: cloud DNS still works
dig app.cloud.corp.local   # still returns 10.1.1.50 ✓

# 3. From EC2-Cloud: on-prem DNS fails (expected)
dig app.corp.local     # times out ✗

# 4. From App Server: on-prem DNS also fails
dig app.corp.local     # times out ✗

# 5. Restart BIND → automatic recovery
sudo systemctl start named
dig app.corp.local     # returns 10.2.1.20 ✓
```

**Talking point:** In Split DNS, an on-prem DNS failure only affects `corp.local` resolution. Cloud resources keep working. Compare to Scenario 2 (All On-Prem) where BIND failure takes down both environments.

## Cost (Split DNS)

| Component | IPs / Count | Monthly |
|-----------|------------|---------|
| Inbound Resolver Endpoint | 2 IPs (HA) | $182.50 |
| Outbound Resolver Endpoint | 2 IPs (HA) | $182.50 |
| Resolver Rule (`corp.local`) | 1 rule | $73.00 |
| PHZ `cloud.corp.local` | 1 zone | $0.50 |
| DNS queries (est. 1M) | — | $0.40 |
| **Total (Route 53)** | | **~$438/month** |

> The endpoints are the dominant cost. For dev/test, drop to 1 IP per endpoint (single AZ) to cut $182.50/month.

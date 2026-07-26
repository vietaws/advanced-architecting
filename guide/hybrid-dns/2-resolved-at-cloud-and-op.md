## Architecture Overview

VPC A (Cloud - 10.1.0.0/16)
├── Private Subnet (10.1.1.0/24)
│   └── EC2 Instance (private)
├── S3 Gateway Endpoint
└── Route 53 Resolver Endpoints
    ├── Inbound Endpoint (receives queries from on-prem)
    └── Outbound Endpoint (forwards queries to on-prem)

VPC OP (On-Premise Simulation - 10.2.0.0/16)
├── Private Subnet (10.2.1.0/24)
│   ├── DNS Server (BIND/Unbound)
│   └── App Server EC2
└── VPC Peering to VPC A

Route 53 Private Hosted Zone
└── example.cloud (for VPC A resources)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Implementation Guide

### Task 1: Build VPC A with Private EC2

1.1 Create VPC A:
bash
VPC_A_ID=$(aws ec2 create-vpc \
  --cidr-block 10.1.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=VPC-A-Cloud}]' \
  --region ap-southeast-1 \
  --query 'Vpc.VpcId' \
  --output text)

aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_A_ID \
  --enable-dns-hostnames \
  --region ap-southeast-1

aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_A_ID \
  --enable-dns-support \
  --region ap-southeast-1


1.2 Create Private Subnet:
bash
SUBNET_A_PRIVATE=$(aws ec2 create-subnet \
  --vpc-id $VPC_A_ID \
  --cidr-block 10.1.1.0/24 \
  --availability-zone ap-southeast-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=VPC-A-Private}]' \
  --region ap-southeast-1 \
  --query 'Subnet.SubnetId' \
  --output text)


1.3 Create Security Group:
bash
SG_A=$(aws ec2 create-security-group \
  --group-name vpc-a-private-sg \
  --description "Security group for VPC A private EC2" \
  --vpc-id $VPC_A_ID \
  --region ap-southeast-1 \
  --query 'GroupId' \
  --output text)

# Allow SSH from VPC OP
aws ec2 authorize-security-group-ingress \
  --group-id $SG_A \
  --protocol tcp \
  --port 22 \
  --cidr 10.2.0.0/16 \
  --region ap-southeast-1

# Allow ICMP from VPC OP
aws ec2 authorize-security-group-ingress \
  --group-id $SG_A \
  --protocol icmp \
  --port -1 \
  --cidr 10.2.0.0/16 \
  --region ap-southeast-1

# Allow all outbound (default)


1.4 Launch EC2 Instance:
bash
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t3.micro \
  --subnet-id $SUBNET_A_PRIVATE \
  --security-group-ids $SG_A \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=EC2-VPC-A-Private}]' \
  --region ap-southeast-1 \
  --no-associate-public-ip-address


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Task 2: Create S3 Bucket

bash
BUCKET_NAME="hybrid-dns-demo-$(date +%s)"

aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1

aws s3api put-bucket-tagging \
  --bucket $BUCKET_NAME \
  --tagging 'TagSet=[{Key=Name,Value=HybridDNSDemo}]'


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Task 3: Create S3 Gateway Endpoint

bash
# Get route table ID
ROUTE_TABLE_A=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_A_ID" \
  --region ap-southeast-1 \
  --query 'RouteTables[0].RouteTableId' \
  --output text)

# Create S3 Gateway Endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_A_ID \
  --service-name com.amazonaws.ap-southeast-1.s3 \
  --route-table-ids $ROUTE_TABLE_A \
  --region ap-southeast-1 \
  --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=S3-Gateway-Endpoint}]'


Cost: $0 (S3 Gateway Endpoints are free)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Task 4: Create VPC OP with DNS Server

4.1 Create VPC OP:
bash
VPC_OP_ID=$(aws ec2 create-vpc \
  --cidr-block 10.2.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=VPC-OP-OnPrem}]' \
  --region ap-southeast-1 \
  --query 'Vpc.VpcId' \
  --output text)

aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_OP_ID \
  --enable-dns-hostnames \
  --region ap-southeast-1

aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_OP_ID \
  --enable-dns-support \
  --region ap-southeast-1


4.2 Create Subnet:
bash
SUBNET_OP=$(aws ec2 create-subnet \
  --vpc-id $VPC_OP_ID \
  --cidr-block 10.2.1.0/24 \
  --availability-zone ap-southeast-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=VPC-OP-Private}]' \
  --region ap-southeast-1 \
  --query 'Subnet.SubnetId' \
  --output text)


4.3 Create Security Group for DNS Server:
bash
SG_DNS=$(aws ec2 create-security-group \
  --group-name vpc-op-dns-sg \
  --description "Security group for on-prem DNS server" \
  --vpc-id $VPC_OP_ID \
  --region ap-southeast-1 \
  --query 'GroupId' \
  --output text)

# Allow DNS from VPC A (UDP/TCP 53)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_DNS \
  --protocol udp \
  --port 53 \
  --cidr 10.1.0.0/16 \
  --region ap-southeast-1

aws ec2 authorize-security-group-ingress \
  --group-id $SG_DNS \
  --protocol tcp \
  --port 53 \
  --cidr 10.1.0.0/16 \
  --region ap-southeast-1

# Allow DNS from VPC OP
aws ec2 authorize-security-group-ingress \
  --group-id $SG_DNS \
  --protocol udp \
  --port 53 \
  --cidr 10.2.0.0/16 \
  --region ap-southeast-1

aws ec2 authorize-security-group-ingress \
  --group-id $SG_DNS \
  --protocol tcp \
  --port 53 \
  --cidr 10.2.0.0/16 \
  --region ap-southeast-1

# Allow SSH
aws ec2 authorize-security-group-ingress \
  --group-id $SG_DNS \
  --protocol tcp \
  --port 22 \
  --cidr 10.2.0.0/16 \
  --region ap-southeast-1


4.4 Launch DNS Server EC2:
bash
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t3.small \
  --subnet-id $SUBNET_OP \
  --security-group-ids $SG_DNS \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=DNS-Server-OnPrem}]' \
  --region ap-southeast-1 \
  --user-data file://dns-server-setup.sh


4.5 DNS Server Setup Script (dns-server-setup.sh):
bash
#!/bin/bash
# Install BIND DNS server
yum update -y
yum install -y bind bind-utils

# Backup original config
cp /etc/named.conf /etc/named.conf.backup

# Configure BIND
cat > /etc/named.conf << 'EOF'
options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { none; };
    directory "/var/named";
    dump-file "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    allow-query { 10.1.0.0/16; 10.2.0.0/16; };
    recursion yes;
    
    # Forward queries for cloud domain to Route 53 Resolver
    forwarders {
        # Will be replaced with Route 53 Inbound Resolver IPs
        10.1.1.10;
        10.1.1.11;
    };
    
    forward only;
    dnssec-validation no;
};

# Local zone for on-premise
zone "onprem.local" IN {
    type master;
    file "/var/named/onprem.local.zone";
    allow-update { none; };
};

# Reverse zone
zone "2.10.in-addr.arpa" IN {
    type master;
    file "/var/named/10.2.rev";
    allow-update { none; };
};
EOF

# Create forward zone file
cat > /var/named/onprem.local.zone << 'EOF'
$TTL 86400
@   IN  SOA     dns.onprem.local. admin.onprem.local. (
            2026021101  ; Serial
            3600        ; Refresh
            1800        ; Retry
            604800      ; Expire
            86400 )     ; Minimum TTL

@       IN  NS      dns.onprem.local.
dns     IN  A       10.2.1.10
app     IN  A       10.2.1.20
EOF

# Create reverse zone file
cat > /var/named/10.2.rev << 'EOF'
$TTL 86400
@   IN  SOA     dns.onprem.local. admin.onprem.local. (
            2026021101
            3600
            1800
            604800
            86400 )

@       IN  NS      dns.onprem.local.
10.1    IN  PTR     dns.onprem.local.
20.1    IN  PTR     app.onprem.local.
EOF

# Set permissions
chown named:named /var/named/onprem.local.zone
chown named:named /var/named/10.2.rev

# Start and enable BIND
systemctl start named
systemctl enable named

# Configure firewall
firewall-cmd --permanent --add-service=dns
firewall-cmd --reload


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Task 5: Create App Server in VPC OP

bash
SG_APP=$(aws ec2 create-security-group \
  --group-name vpc-op-app-sg \
  --description "Security group for on-prem app server" \
  --vpc-id $VPC_OP_ID \
  --region ap-southeast-1 \
  --query 'GroupId' \
  --output text)

# Allow SSH and HTTP
aws ec2 authorize-security-group-ingress \
  --group-id $SG_APP \
  --protocol tcp \
  --port 22 \
  --cidr 10.2.0.0/16 \
  --region ap-southeast-1

aws ec2 authorize-security-group-ingress \
  --group-id $SG_APP \
  --protocol tcp \
  --port 80 \
  --cidr 10.1.0.0/16 \
  --region ap-southeast-1

# Launch App Server
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t3.micro \
  --subnet-id $SUBNET_OP \
  --security-group-ids $SG_APP \
  --private-ip-address 10.2.1.20 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=App-Server-OnPrem}]' \
  --region ap-southeast-1


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Task 6 & 7: Setup Route 53 Resolver and Private Hosted Zone

6.1 Create VPC Peering:
bash
PEERING_ID=$(aws ec2 create-vpc-peering-connection \
  --vpc-id $VPC_A_ID \
  --peer-vpc-id $VPC_OP_ID \
  --tag-specifications 'ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=VPC-A-to-VPC-OP}]' \
  --region ap-southeast-1 \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' \
  --output text)

# Accept peering
aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id $PEERING_ID \
  --region ap-southeast-1

# Update route tables
ROUTE_TABLE_OP=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_OP_ID" \
  --region ap-southeast-1 \
  --query 'RouteTables[0].RouteTableId' \
  --output text)

aws ec2 create-route \
  --route-table-id $ROUTE_TABLE_A \
  --destination-cidr-block 10.2.0.0/16 \
  --vpc-peering-connection-id $PEERING_ID \
  --region ap-southeast-1

aws ec2 create-route \
  --route-table-id $ROUTE_TABLE_OP \
  --destination-cidr-block 10.1.0.0/16 \
  --vpc-peering-connection-id $PEERING_ID \
  --region ap-southeast-1


6.2 Create Route 53 Private Hosted Zone:
bash
# Create hosted zone
HOSTED_ZONE_ID=$(aws route53 create-hosted-zone \
  --name example.cloud \
  --vpc VPCRegion=ap-southeast-1,VPCId=$VPC_A_ID \
  --caller-reference $(date +%s) \
  --hosted-zone-config Comment="Private hosted zone for VPC A",PrivateZone=true \
  --query 'HostedZone.Id' \
  --output text)

# Associate with VPC OP
aws route53 associate-vpc-with-hosted-zone \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --vpc VPCRegion=ap-southeast-1,VPCId=$VPC_OP_ID

# Create DNS record for EC2 in VPC A
EC2_A_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=EC2-VPC-A-Private" "Name=instance-state-name,Values=running" \
  --region ap-southeast-1 \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

cat > change-batch.json << EOF
{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "app.example.cloud",
      "Type": "A",
      "TTL": 300,
      "ResourceRecords": [{"Value": "$EC2_A_IP"}]
    }
  }]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch file://change-batch.json


6.3 Create Route 53 Resolver Inbound Endpoint:
bash
# Create security group for resolver endpoints
SG_RESOLVER=$(aws ec2 create-security-group \
  --group-name resolver-endpoint-sg \
  --description "Security group for Route 53 Resolver endpoints" \
  --vpc-id $VPC_A_ID \
  --region ap-southeast-1 \
  --query 'GroupId' \
  --output text)

# Allow DNS from VPC OP
aws ec2 authorize-security-group-ingress \
  --group-id $SG_RESOLVER \
  --protocol udp \
  --port 53 \
  --cidr 10.2.0.0/16 \
  --region ap-southeast-1

aws ec2 authorize-security-group-ingress \
  --group-id $SG_RESOLVER \
  --protocol tcp \
  --port 53 \
  --cidr 10.2.0.0/16 \
  --region ap-southeast-1

# Create second subnet for high availability
SUBNET_A_PRIVATE_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_A_ID \
  --cidr-block 10.1.2.0/24 \
  --availability-zone ap-southeast-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=VPC-A-Private-2}]' \
  --region ap-southeast-1 \
  --query 'Subnet.SubnetId' \
  --output text)

# Create Inbound Endpoint
INBOUND_ENDPOINT_ID=$(aws route53resolver create-resolver-endpoint \
  --creator-request-id $(date +%s) \
  --name "Inbound-Endpoint-VPC-A" \
  --security-group-ids $SG_RESOLVER \
  --direction INBOUND \
  --ip-addresses SubnetId=$SUBNET_A_PRIVATE,Ip=10.1.1.10 SubnetId=$SUBNET_A_PRIVATE_2,Ip=10.1.2.10 \
  --region ap-southeast-1 \
  --query 'ResolverEndpoint.Id' \
  --output text)


Cost: $0.125/hour per IP address × 2 IPs = $0.25/hour = $182.50/month

6.4 Create Route 53 Resolver Outbound Endpoint:
bash
# Create Outbound Endpoint
OUTBOUND_ENDPOINT_ID=$(aws route53resolver create-resolver-endpoint \
  --creator-request-id $(date +%s) \
  --name "Outbound-Endpoint-VPC-A" \
  --security-group-ids $SG_RESOLVER \
  --direction OUTBOUND \
  --ip-addresses SubnetId=$SUBNET_A_PRIVATE,Ip=10.1.1.11 SubnetId=$SUBNET_A_PRIVATE_2,Ip=10.1.2.11 \
  --region ap-southeast-1 \
  --query 'ResolverEndpoint.Id' \
  --output text)


Cost: $0.125/hour per IP address × 2 IPs = $0.25/hour = $182.50/month

6.5 Create Resolver Rule for On-Premise Domain:
bash
# Get DNS server IP
DNS_SERVER_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=DNS-Server-OnPrem" "Name=instance-state-name,Values=running" \
  --region ap-southeast-1 \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

# Create resolver rule
RULE_ID=$(aws route53resolver create-resolver-rule \
  --creator-request-id $(date +%s) \
  --name "Forward-to-OnPrem-DNS" \
  --rule-type FORWARD \
  --domain-name onprem.local \
  --resolver-endpoint-id $OUTBOUND_ENDPOINT_ID \
  --target-ips Ip=$DNS_SERVER_IP,Port=53 \
  --region ap-southeast-1 \
  --query 'ResolverRule.Id' \
  --output text)

# Associate rule with VPC A
aws route53resolver associate-resolver-rule \
  --resolver-rule-id $RULE_ID \
  --vpc-id $VPC_A_ID \
  --region ap-southeast-1


Cost: $0.10/hour per rule = $73/month

6.6 Update On-Premise DNS Server Forwarders:

SSH to DNS server and update /etc/named.conf:
bash
# Replace forwarders section with actual Inbound Resolver IPs
forwarders {
    10.1.1.10;
    10.1.2.10;
};


Restart BIND:
bash
systemctl restart named


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## DNS Resolution Flow

### Cloud to On-Premise (VPC A → VPC OP)

EC2 in VPC A queries "app.onprem.local"
  ↓
VPC DNS Resolver (10.1.0.2)
  ↓
Route 53 Resolver Rule matches "onprem.local"
  ↓
Outbound Endpoint (10.1.1.11 or 10.1.2.11)
  ↓
VPC Peering
  ↓
On-Prem DNS Server (10.2.1.10)
  ↓
Returns 10.2.1.20


### On-Premise to Cloud (VPC OP → VPC A)

App Server in VPC OP queries "app.example.cloud"
  ↓
On-Prem DNS Server (10.2.1.10)
  ↓
Forwarder to Route 53 Inbound Resolver
  ↓
VPC Peering
  ↓
Inbound Endpoint (10.1.1.10 or 10.1.2.10)
  ↓
Route 53 Private Hosted Zone
  ↓
Returns EC2 private IP


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Task 8: Cost Analysis

### Monthly Costs

| Component | Quantity | Unit Cost | Monthly Cost | Notes |
|-----------|----------|-----------|--------------|-------|
| Compute | | | | |
| EC2 t3.micro (VPC A) | 1 | $0.0104/hour | $7.59 | 730 hours |
| EC2 t3.small (DNS) | 1 | $0.0208/hour | $15.18 | 730 hours |
| EC2 t3.micro (App) | 1 | $0.0104/hour | $7.59 | 730 hours |
| Storage | | | | |
| EBS gp3 8GB × 3 | 24 GB | $0.08/GB | $1.92 | Default root volumes |
| Networking | | | | |
| VPC Peering | 1 | $0 | $0 | No attachment fee |
| Data Transfer (peering) | ~1 GB | $0.01/GB | $0.01 | Minimal DNS traffic |
| S3 Gateway Endpoint | 1 | $0 | $0 | Free |
| Route 53 | | | | |
| Private Hosted Zone | 1 | $0.50/month | $0.50 | First 25 zones |
| Inbound Resolver | 2 IPs | $0.125/hour | $182.50 | High availability |
| Outbound Resolver | 2 IPs | $0.125/hour | $182.50 | High availability |
| Resolver Rule | 1 | $0.10/hour | $73.00 | Forward to on-prem |
| DNS Queries | 1M | $0.40/M | $0.40 | Estimated |
| S3 | | | | |
| S3 Storage | 1 GB | $0.023/GB | $0.02 | Minimal |
| Total | | | $471.21 | |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Optimization Strategies

### 1. Reduce Resolver Endpoints to Single AZ (Not Recommended for Production)

Inbound: 1 IP instead of 2 = $91.25/month (save $91.25)
Outbound: 1 IP instead of 2 = $91.25/month (save $91.25)
Total savings: $182.50/month
New total: $288.71/month


Risk: No high availability, single point of failure

### 2. Use Smaller EC2 Instances

DNS Server: t3.micro instead of t3.small = save $7.59/month


Risk: May not handle high DNS query volume

### 3. Use Spot Instances for Non-Production

All EC2 as Spot (70% discount) = save ~$21.50/month


Risk: Instances can be terminated

### 4. Consolidate DNS and App Server

Run app on DNS server = save $7.59 + $0.64 (EBS) = $8.23/month


Risk: Not realistic for production, poor separation of concerns

### 5. Use AWS Systems Manager Session Manager Instead of Bastion

No additional cost, eliminates need for public IPs or bastion hosts


### 6. Reserved Instances (1-year commitment)

EC2 savings: ~40% = save ~$12/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Optimized Architecture for Cost (Non-Production)

| Component | Change | New Cost | Savings |
|-----------|--------|----------|---------|
| Inbound Resolver | 1 IP (single AZ) | $91.25 | -$91.25 |
| Outbound Resolver | 1 IP (single AZ) | $91.25 | -$91.25 |
| DNS Server | t3.micro | $7.59 | -$7.59 |
| New Total | | $281.12 | -$190.09 |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Testing the Setup

### Test 1: Cloud to On-Premise DNS Resolution

bash
# SSH to EC2 in VPC A
# Query on-premise domain
dig app.onprem.local

# Expected: 10.2.1.20
# Should resolve via Outbound Resolver → On-Prem DNS


### Test 2: On-Premise to Cloud DNS Resolution

bash
# SSH to App Server in VPC OP
# Query cloud domain
dig app.example.cloud

# Expected: EC2 VPC A private IP
# Should resolve via On-Prem DNS → Inbound Resolver → Route 53 PHZ


### Test 3: S3 Access via Gateway Endpoint

bash
# SSH to EC2 in VPC A
aws s3 ls s3://$BUCKET_NAME

# Should work without internet gateway
# Traffic goes through S3 Gateway Endpoint


### Test 4: Verify DNS Query Path

bash
# On DNS Server (VPC OP)
tail -f /var/log/messages | grep named

# Should see queries being forwarded to Route 53 Inbound Resolver


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Best Practices Implemented

1. High Availability: 2 AZs for Route 53 Resolver endpoints
2. Security: Private subnets, no public IPs, security groups with least privilege
3. Cost Optimization: VPC Peering instead of VPN/DX, S3 Gateway Endpoint (free)
4. DNS Hierarchy: On-prem DNS as authoritative for on-prem, Route 53 for cloud
5. Scalability: Route 53 Resolver handles high query volumes automatically
6. Monitoring: Enable VPC Flow Logs and Route 53 Resolver query logging

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Additional Recommendations

### Enable Route 53 Resolver Query Logging

bash
# Create CloudWatch Log Group
aws logs create-log-group \
  --log-group-name /aws/route53/resolver-queries \
  --region ap-southeast-1

# Create Resolver Query Log Config
aws route53resolver create-resolver-query-log-config \
  --name "resolver-query-logs" \
  --destination-arn "arn:aws:logs:ap-southeast-1:123456789012:log-group:/aws/route53/resolver-queries" \
  --region ap-southeast-1

# Associate with VPC
aws route53resolver associate-resolver-query-log-config \
  --resolver-query-log-config-id rqlc-xxxxx \
  --resource-id $VPC_A_ID \
  --region ap-southeast-1


Cost: CloudWatch Logs ingestion ~$0.50/GB

### Enable VPC Flow Logs

bash
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids $VPC_A_ID $VPC_OP_ID \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs \
  --deliver-logs-permission-arn arn:aws:iam::123456789012:role/flowlogsRole \
  --region ap-southeast-1


Cost: ~$0.50/GB ingested + storage

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

Total Monthly Cost: $471.21 (production-ready with HA)
Optimized Cost: $281.12 (single AZ, acceptable for demo/dev)

Key Cost Drivers:
1. Route 53 Resolver Endpoints: $365/month (77% of total)
2. EC2 Instances: $30.36/month (6% of total)
3. Resolver Rules: $73/month (15% of total)

This architecture demonstrates:
- Hybrid DNS resolution between cloud and on-premise
- Secure private connectivity via VPC Peering
- Cost-effective S3 access via Gateway Endpoint
- Production-ready high availability with multi-AZ resolvers
- Proper DNS hierarchy and forwarding rules
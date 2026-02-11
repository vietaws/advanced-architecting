update the guide for architecture #002 if I want all dns resolution will happen on aws cloud (VPC A) via private hosted zone on route 53. on-premise still has their own dns server.

> I'll update the architecture where all DNS resolution happens in AWS (VPC A) via Route 53, while on-premise keeps its DNS 
server for local records.

## Updated Architecture Overview

VPC A (Cloud - 10.1.0.0/16) - DNS Authority
├── Private Subnet (10.1.1.0/24)
│   └── EC2 Instance (private)
├── S3 Gateway Endpoint
└── Route 53 Resolver Endpoints
    └── Inbound Endpoint (receives ALL queries from on-prem)

VPC OP (On-Premise Simulation - 10.2.0.0/16)
├── Private Subnet (10.2.1.0/24)
│   ├── DNS Server (forwards ALL queries to AWS)
│   └── App Server EC2
└── VPC Peering to VPC A

Route 53 Private Hosted Zones
├── example.cloud (for VPC A cloud resources)
└── onprem.local (for VPC OP on-premise resources)


Key Change: Route 53 becomes authoritative for BOTH cloud and on-premise domains. On-premise DNS server acts as a forwarder 
only.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Updated Implementation

### Tasks 1-5: Same as Before

(VPC A, S3, Gateway Endpoint, VPC OP, EC2 instances remain the same)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Task 6 & 7: Updated DNS Configuration

Step 1: Create VPC Peering (Same as Before)

bash
PEERING_ID=$(aws ec2 create-vpc-peering-connection \
  --vpc-id $VPC_A_ID \
  --peer-vpc-id $VPC_OP_ID \
  --tag-specifications 'ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=VPC-A-to-VPC-OP}]' \
  --region ap-southeast-1 \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' \
  --output text)

aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id $PEERING_ID \
  --region ap-southeast-1

# Update route tables
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


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


Step 2: Create Route 53 Private Hosted Zones (Both Domains)

2.1 Cloud Domain (example.cloud):
bash
HOSTED_ZONE_CLOUD=$(aws route53 create-hosted-zone \
  --name example.cloud \
  --vpc VPCRegion=ap-southeast-1,VPCId=$VPC_A_ID \
  --caller-reference cloud-$(date +%s) \
  --hosted-zone-config Comment="Private hosted zone for cloud resources",PrivateZone=true \
  --query 'HostedZone.Id' \
  --output text)

# Associate with VPC OP
aws route53 associate-vpc-with-hosted-zone \
  --hosted-zone-id $HOSTED_ZONE_CLOUD \
  --vpc VPCRegion=ap-southeast-1,VPCId=$VPC_OP_ID


2.2 On-Premise Domain (onprem.local) - NEW:
bash
HOSTED_ZONE_ONPREM=$(aws route53 create-hosted-zone \
  --name onprem.local \
  --vpc VPCRegion=ap-southeast-1,VPCId=$VPC_A_ID \
  --caller-reference onprem-$(date +%s) \
  --hosted-zone-config Comment="Private hosted zone for on-premise resources",PrivateZone=true \
  --query 'HostedZone.Id' \
  --output text)

# Associate with VPC OP
aws route53 associate-vpc-with-hosted-zone \
  --hosted-zone-id $HOSTED_ZONE_ONPREM \
  --vpc VPCRegion=ap-southeast-1,VPCId=$VPC_OP_ID


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


Step 3: Create DNS Records in Route 53

3.1 Cloud Resources:
bash
# Get EC2 IP in VPC A
EC2_A_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=EC2-VPC-A-Private" "Name=instance-state-name,Values=running" \
  --region ap-southeast-1 \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

cat > cloud-records.json << EOF
{
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "app.example.cloud",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "$EC2_A_IP"}]
      }
    },
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "web.example.cloud",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "$EC2_A_IP"}]
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_CLOUD \
  --change-batch file://cloud-records.json


3.2 On-Premise Resources (in Route 53) - NEW:
bash
# Get on-premise server IPs
DNS_SERVER_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=DNS-Server-OnPrem" "Name=instance-state-name,Values=running" \
  --region ap-southeast-1 \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

APP_SERVER_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=App-Server-OnPrem" "Name=instance-state-name,Values=running" \
  --region ap-southeast-1 \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

cat > onprem-records.json << EOF
{
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "dns.onprem.local",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "$DNS_SERVER_IP"}]
      }
    },
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "app.onprem.local",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "$APP_SERVER_IP"}]
      }
    },
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "db.onprem.local",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "10.2.1.30"}]
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ONPREM \
  --change-batch file://onprem-records.json


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


Step 4: Create Route 53 Inbound Resolver ONLY

bash
# Create security group for resolver endpoint
SG_RESOLVER=$(aws ec2 create-security-group \
  --group-name resolver-endpoint-sg \
  --description "Security group for Route 53 Resolver inbound endpoint" \
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

# Allow DNS from VPC A (for testing)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_RESOLVER \
  --protocol udp \
  --port 53 \
  --cidr 10.1.0.0/16 \
  --region ap-southeast-1

# Create second subnet for HA
SUBNET_A_PRIVATE_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_A_ID \
  --cidr-block 10.1.2.0/24 \
  --availability-zone ap-southeast-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=VPC-A-Private-2}]' \
  --region ap-southeast-1 \
  --query 'Subnet.SubnetId' \
  --output text)

# Update route table for new subnet
aws ec2 associate-route-table \
  --route-table-id $ROUTE_TABLE_A \
  --subnet-id $SUBNET_A_PRIVATE_2 \
  --region ap-southeast-1

# Add peering route to new subnet's route table
aws ec2 create-route \
  --route-table-id $ROUTE_TABLE_A \
  --destination-cidr-block 10.2.0.0/16 \
  --vpc-peering-connection-id $PEERING_ID \
  --region ap-southeast-1

# Create Inbound Endpoint
INBOUND_ENDPOINT_ID=$(aws route53resolver create-resolver-endpoint \
  --creator-request-id inbound-$(date +%s) \
  --name "Inbound-Endpoint-VPC-A" \
  --security-group-ids $SG_RESOLVER \
  --direction INBOUND \
  --ip-addresses SubnetId=$SUBNET_A_PRIVATE,Ip=10.1.1.10 SubnetId=$SUBNET_A_PRIVATE_2,Ip=10.1.2.10 \
  --region ap-southeast-1 \
  --query 'ResolverEndpoint.Id' \
  --output text)

# Wait for endpoint to be operational
aws route53resolver get-resolver-endpoint \
  --resolver-endpoint-id $INBOUND_ENDPOINT_ID \
  --region ap-southeast-1 \
  --query 'ResolverEndpoint.Status'


Cost: $0.125/hour × 2 IPs = $182.50/month

Note: NO Outbound Resolver needed - saves $182.50/month!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


Step 5: Configure On-Premise DNS Server as Forwarder

Updated DNS Server Configuration (dns-server-setup.sh):

bash
#!/bin/bash
# Install BIND DNS server
yum update -y
yum install -y bind bind-utils

# Backup original config
cp /etc/named.conf /etc/named.conf.backup

# Configure BIND as pure forwarder
cat > /etc/named.conf << 'EOF'
options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { none; };
    directory "/var/named";
    dump-file "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    
    # Allow queries from on-premise network
    allow-query { 10.2.0.0/16; };
    
    # Enable recursion
    recursion yes;
    
    # Forward ALL queries to Route 53 Resolver Inbound Endpoint
    forwarders {
        10.1.1.10;
        10.1.2.10;
    };
    
    # Forward all queries (don't try to resolve locally)
    forward only;
    
    # Disable DNSSEC validation (Route 53 handles this)
    dnssec-validation no;
};

# Optional: Local cache zone for performance
zone "." IN {
    type hint;
    file "named.ca";
};

# Logging for troubleshooting
logging {
    channel default_debug {
        file "data/named.run";
        severity dynamic;
    };
    channel query_log {
        file "/var/log/named/query.log" versions 3 size 5m;
        severity info;
        print-time yes;
        print-category yes;
    };
    category queries { query_log; };
};
EOF

# Create log directory
mkdir -p /var/log/named
chown named:named /var/log/named

# Start and enable BIND
systemctl start named
systemctl enable named

# Configure firewall
firewall-cmd --permanent --add-service=dns
firewall-cmd --reload

# Test DNS resolution
echo "Testing DNS resolution..."
dig app.example.cloud @127.0.0.1
dig app.onprem.local @127.0.0.1
EOF


Apply configuration to existing DNS server:

bash
# SSH to DNS server and run:
sudo tee /etc/named.conf > /dev/null << 'EOF'
options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { none; };
    directory "/var/named";
    allow-query { 10.2.0.0/16; };
    recursion yes;
    
    forwarders {
        10.1.1.10;
        10.1.2.10;
    };
    
    forward only;
    dnssec-validation no;
};

logging {
    channel query_log {
        file "/var/log/named/query.log" versions 3 size 5m;
        severity info;
        print-time yes;
    };
    category queries { query_log; };
};
EOF

sudo mkdir -p /var/log/named
sudo chown named:named /var/log/named
sudo systemctl restart named


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


Step 6: Configure VPC OP DHCP Options (Optional but Recommended)

bash
# Create DHCP options set pointing to on-prem DNS
DHCP_OPTIONS=$(aws ec2 create-dhcp-options \
  --dhcp-configurations \
    "Key=domain-name-servers,Values=$DNS_SERVER_IP" \
    "Key=domain-name,Values=onprem.local" \
  --tag-specifications 'ResourceType=dhcp-options,Tags=[{Key=Name,Value=VPC-OP-DHCP}]' \
  --region ap-southeast-1 \
  --query 'DhcpOptions.DhcpOptionsId' \
  --output text)

# Associate with VPC OP
aws ec2 associate-dhcp-options \
  --dhcp-options-id $DHCP_OPTIONS \
  --vpc-id $VPC_OP_ID \
  --region ap-southeast-1


Note: VPC A uses default DHCP options (AmazonProvidedDNS at 10.1.0.2), which automatically queries Route 53 Private Hosted 
Zones.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Updated DNS Resolution Flow

### Cloud to Cloud (VPC A → VPC A)

EC2 in VPC A queries "app.example.cloud"
  ↓
VPC DNS Resolver (10.1.0.2)
  ↓
Route 53 Private Hosted Zone (example.cloud)
  ↓
Returns EC2 private IP


### Cloud to On-Premise (VPC A → VPC OP)

EC2 in VPC A queries "app.onprem.local"
  ↓
VPC DNS Resolver (10.1.0.2)
update the guide for architecture #002 if I want all dns resolution will happen on on-premises (VPC OP). on-premise still has their own dns server.

> I'll update the architecture to centralize all DNS resolution on the on-premise DNS server.

## Updated Architecture Overview

VPC A (Cloud - 10.1.0.0/16)
├── Private Subnet (10.1.1.0/24)
│   └── EC2 Instance (private)
│       └── DNS: Points to On-Prem DNS (10.2.1.10)
├── S3 Gateway Endpoint
└── DHCP Options Set (custom DNS)

VPC OP (On-Premise Simulation - 10.2.0.0/16)
├── Private Subnet (10.2.1.0/24)
│   ├── DNS Server (BIND) - CENTRAL DNS
│   │   ├── Authoritative for onprem.local
│   │   ├── Authoritative for example.cloud
│   │   └── Forwards AWS service queries to VPC DNS
│   └── App Server EC2
└── VPC Peering to VPC A

Route 53 (Optional)
└── Private Hosted Zone (backup/migration path)


Key Change: All DNS queries from both VPCs go to on-premise DNS server first.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Updated Implementation Guide

### Changes from Previous Architecture

Remove:
- ❌ Route 53 Resolver Inbound Endpoint
- ❌ Route 53 Resolver Outbound Endpoint  
- ❌ Route 53 Resolver Rules
- ❌ Route 53 Private Hosted Zone (optional, can keep for future)

Add:
- ✅ Custom DHCP Options Set for VPC A
- ✅ Enhanced on-premise DNS configuration
- ✅ Conditional forwarding for AWS services

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step-by-Step Changes

### 1. Create Custom DHCP Options Set for VPC A

bash
# Create DHCP options pointing to on-prem DNS
DHCP_OPTIONS_ID=$(aws ec2 create-dhcp-options \
  --dhcp-configurations \
    "Key=domain-name,Values=example.cloud" \
    "Key=domain-name-servers,Values=10.2.1.10" \
  --tag-specifications 'ResourceType=dhcp-options,Tags=[{Key=Name,Value=Custom-DNS-OnPrem}]' \
  --region ap-southeast-1 \
  --query 'DhcpOptions.DhcpOptionsId' \
  --output text)

# Associate with VPC A
aws ec2 associate-dhcp-options \
  --dhcp-options-id $DHCP_OPTIONS_ID \
  --vpc-id $VPC_A_ID \
  --region ap-southeast-1


Important: Existing EC2 instances need to be rebooted or renew DHCP lease to pick up new DNS settings.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 2. Updated DNS Server Configuration

Enhanced BIND Configuration (dns-server-setup.sh):

bash
#!/bin/bash
# Install BIND DNS server
yum update -y
yum install -y bind bind-utils

# Backup original config
cp /etc/named.conf /etc/named.conf.backup

# Configure BIND as central DNS
cat > /etc/named.conf << 'EOF'
options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { none; };
    directory "/var/named";
    dump-file "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    
    # Allow queries from both VPCs
    allow-query { 10.1.0.0/16; 10.2.0.0/16; };
    
    # Enable recursion for all queries
    recursion yes;
    
    # Forward AWS service queries to VPC DNS resolver
    # VPC A DNS resolver is always at VPC CIDR + 2
    # For 10.1.0.0/16, DNS is at 10.1.0.2
    
    dnssec-validation no;
    
    # Query logging
    querylog yes;
};

# Logging configuration
logging {
    channel default_debug {
        file "data/named.run";
        severity dynamic;
    };
    channel query_log {
        file "/var/log/named/query.log" versions 3 size 10m;
        severity info;
        print-time yes;
        print-category yes;
    };
    category queries { query_log; };
};

# Local zone for on-premise
zone "onprem.local" IN {
    type master;
    file "/var/named/onprem.local.zone";
    allow-update { none; };
};

# Cloud zone (managed by on-prem DNS)
zone "example.cloud" IN {
    type master;
    file "/var/named/example.cloud.zone";
    allow-update { none; };
};

# Reverse zone for VPC OP
zone "2.10.in-addr.arpa" IN {
    type master;
    file "/var/named/10.2.rev";
    allow-update { none; };
};

# Reverse zone for VPC A
zone "1.10.in-addr.arpa" IN {
    type master;
    file "/var/named/10.1.rev";
    allow-update { none; };
};

# Forward AWS service domains to VPC DNS
zone "amazonaws.com" IN {
    type forward;
    forward only;
    forwarders { 10.1.0.2; };
};

zone "ap-southeast-1.compute.internal" IN {
    type forward;
    forward only;
    forwarders { 10.1.0.2; };
};

# Forward other queries to public DNS (for internet domains)
zone "." IN {
    type forward;
    forward first;
    forwarders { 8.8.8.8; 1.1.1.1; };
};
EOF

# Create log directory
mkdir -p /var/log/named
chown named:named /var/log/named

# Create on-premise zone file
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
db      IN  A       10.2.1.30
EOF

# Create cloud zone file (manually managed)
cat > /var/named/example.cloud.zone << 'EOF'
$TTL 86400
@   IN  SOA     dns.onprem.local. admin.onprem.local. (
            2026021101  ; Serial
            3600        ; Refresh
            1800        ; Retry
            604800      ; Expire
            86400 )     ; Minimum TTL

@           IN  NS      dns.onprem.local.
app         IN  A       10.1.1.50
web         IN  A       10.1.1.51
api         IN  A       10.1.1.52
EOF

# Create reverse zone for VPC OP
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
30.1    IN  PTR     db.onprem.local.
EOF

# Create reverse zone for VPC A
cat > /var/named/10.1.rev << 'EOF'
$TTL 86400
@   IN  SOA     dns.onprem.local. admin.onprem.local. (
            2026021101
            3600
            1800
            604800
            86400 )

@       IN  NS      dns.onprem.local.
50.1    IN  PTR     app.example.cloud.
51.1    IN  PTR     web.example.cloud.
52.1    IN  PTR     api.example.cloud.
EOF

# Set permissions
chown named:named /var/named/*.zone
chown named:named /var/named/*.rev

# Check configuration
named-checkconf /etc/named.conf
named-checkzone onprem.local /var/named/onprem.local.zone
named-checkzone example.cloud /var/named/example.cloud.zone

# Start and enable BIND
systemctl start named
systemctl enable named

# Configure firewall
firewall-cmd --permanent --add-service=dns
firewall-cmd --reload

echo "DNS Server configured successfully"
echo "DNS Server IP: $(hostname -I | awk '{print $1}')"
EOF


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 3. Update DNS Records for VPC A Resources

Script to add EC2 instances to DNS:

bash
#!/bin/bash
# Get EC2 private IP
EC2_A_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=EC2-VPC-A-Private" "Name=instance-state-name,Values=running" \
  --region ap-southeast-1 \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

# SSH to DNS server and update zone file
ssh ec2-user@10.2.1.10 << EOF
sudo sed -i "/^api/d" /var/named/example.cloud.zone
echo "app         IN  A       $EC2_A_IP" | sudo tee -a /var/named/example.cloud.zone

# Increment serial number
sudo sed -i 's/2026021101/2026021102/' /var/named/example.cloud.zone

# Update reverse zone
LAST_OCTET=\$(echo $EC2_A_IP | cut -d. -f4)
sudo sed -i "/^\${LAST_OCTET}.1/d" /var/named/10.1.rev
echo "\${LAST_OCTET}.1    IN  PTR     app.example.cloud." | sudo tee -a /var/named/10.1.rev

# Reload BIND
sudo rndc reload
EOF


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 4. Configure VPC OP to Use Local DNS

VPC OP already uses local DNS by default, but verify:

bash
# VPC OP uses VPC DNS resolver at 10.2.0.2
# Which forwards to on-prem DNS via DHCP options

# Create DHCP options for VPC OP (if not default)
DHCP_OPTIONS_OP=$(aws ec2 create-dhcp-options \
  --dhcp-configurations \
    "Key=domain-name,Values=onprem.local" \
    "Key=domain-name-servers,Values=10.2.1.10" \
  --tag-specifications 'ResourceType=dhcp-options,Tags=[{Key=Name,Value=OnPrem-DNS}]' \
  --region ap-southeast-1 \
  --query 'DhcpOptions.DhcpOptionsId' \
  --output text)

aws ec2 associate-dhcp-options \
  --dhcp-options-id $DHCP_OPTIONS_OP \
  --vpc-id $VPC_OP_ID \
  --region ap-southeast-1


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 5. Reboot EC2 Instances to Apply New DNS Settings

bash
# Reboot EC2 in VPC A to pick up new DHCP options
aws ec2 reboot-instances \
  --instance-ids $(aws ec2 describe-instances \
    --filters "Name=vpc-id,Values=$VPC_A_ID" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text) \
  --region ap-southeast-1

# Reboot EC2 in VPC OP
aws ec2 reboot-instances \
  --instance-ids $(aws ec2 describe-instances \
    --filters "Name=vpc-id,Values=$VPC_OP_ID" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text) \
  --region ap-southeast-1


Alternative (without reboot):
bash
# SSH to each instance and renew DHCP
sudo dhclient -r && sudo dhclient


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Updated DNS Resolution Flow

### Cloud to On-Premise (VPC A → VPC OP)

EC2 in VPC A queries "app.onprem.local"
  ↓
Custom DHCP Options → 10.2.1.10
  ↓
VPC Peering
  ↓
On-Prem DNS Server (10.2.1.10)
  ↓
Authoritative for onprem.local
  ↓
Returns 10.2.1.20


### On-Premise to Cloud (VPC OP → VPC A)

App Server in VPC OP queries "app.example.cloud"
  ↓
DHCP Options → 10.2.1.10
  ↓
On-Prem DNS Server (10.2.1.10)
  ↓
Authoritative for example.cloud
  ↓
Returns 10.1.1.50


### AWS Service Queries (S3, EC2 API, etc.)

EC2 in VPC A queries "s3.ap-southeast-1.amazonaws.com"
  ↓
On-Prem DNS Server (10.2.1.10)
  ↓
Conditional forwarder for amazonaws.com
  ↓
VPC DNS Resolver (10.1.0.2)
  ↓
Returns AWS service endpoint


### Internet Domain Queries

Any EC2 queries "google.com"
  ↓
On-Prem DNS Server (10.2.1.10)
  ↓
Forward to public DNS (8.8.8.8)
  ↓
Returns public IP


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Updated Cost Analysis

### Monthly Costs (Centralized DNS)

| Component | Quantity | Unit Cost | Monthly Cost | Change |
|-----------|----------|-----------|--------------|--------|
| Compute | | | | |
| EC2 t3.micro (VPC A) | 1 | $0.0104/hour | $7.59 | Same |
| EC2 t3.small (DNS) | 1 | $0.0208/hour | $15.18 | Same |
| EC2 t3.micro (App) | 1 | $0.0104/hour | $7.59 | Same |
| Storage | | | | |
| EBS gp3 8GB × 3 | 24 GB | $0.08/GB | $1.92 | Same |
| Networking | | | | |
| VPC Peering | 1 | $0 | $0 | Same |
| Data Transfer (peering) | ~1 GB | $0.01/GB | $0.01 | Same |
| S3 Gateway Endpoint | 1 | $0 | $0 | Same |
| Route 53 | | | | |
| Inbound Resolver | 2 IPs | $0.125/hour | $0 | REMOVED |
| Outbound Resolver | 2 IPs | $0.125/hour | $0 | REMOVED |
| Resolver Rule | 1 | $0.10/hour | $0 | REMOVED |
| Private Hosted Zone (optional) | 1 | $0.50/month | $0.50 | Optional |
| S3 | | | | |
| S3 Storage | 1 GB | $0.023/GB | $0.02 | Same |
| Total | | | $32.81 | -$438.40 |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Comparison

| Architecture | Monthly Cost | Savings |
|--------------|--------------|---------|
| Original (Route 53 Resolver) | $471.21 | - |
| Centralized On-Prem DNS | $32.81 | -$438.40 (93%) |

Massive savings by eliminating Route 53 Resolver endpoints!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Advantages of Centralized On-Premise DNS

### 1. Cost Savings
- Eliminates $438.40/month in Route 53 Resolver costs
- 93% reduction in total infrastructure cost

### 2. Simplified Management
- Single DNS server to manage
- All DNS records in one place
- Easier troubleshooting

### 3. Centralized Control
- On-premise team controls all DNS
- Consistent DNS policies
- Single source of truth

### 4. Flexibility
- Easy to add/modify DNS records
- No AWS API calls needed for DNS changes
- Faster DNS updates

### 5. Compliance
- Some organizations require on-premise DNS control
- Audit trail in one location
- Meets regulatory requirements

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Disadvantages & Considerations

### 1. Single Point of Failure
- DNS server failure affects both VPCs
- **Mitigation:** Deploy secondary DNS server

### 2. Latency
- All DNS queries cross VPC peering
- Additional ~1-2ms latency
- **Impact:** Minimal for most workloads

### 3. Scalability
- DNS server must handle all queries
- **Mitigation:** Use larger instance or multiple DNS servers

### 4. Manual DNS Management
- No automatic DNS registration for EC2
- Must manually update zone files
- **Mitigation:** Automate with scripts or dynamic DNS

### 5. AWS Service Dependencies
- Must forward AWS service queries to VPC DNS
- Requires proper conditional forwarding
- **Risk:** Misconfiguration breaks AWS API access

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## High Availability Setup (Recommended)

### Deploy Secondary DNS Server

bash
# Launch secondary DNS server
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t3.small \
  --subnet-id $SUBNET_OP \
  --private-ip-address 10.2.1.11 \
  --security-group-ids $SG_DNS \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=DNS-Server-Secondary}]' \
  --region ap-southeast-1 \
  --user-data file://dns-secondary-setup.sh


Configure as BIND slave:

bash
# On secondary DNS server
cat > /etc/named.conf << 'EOF'
options {
    listen-on port 53 { any; };
    allow-query { 10.1.0.0/16; 10.2.0.0/16; };
    recursion yes;
    dnssec-validation no;
};

zone "onprem.local" IN {
    type slave;
    file "slaves/onprem.local.zone";
    masters { 10.2.1.10; };
};

zone "example.cloud" IN {
    type slave;
    file "slaves/example.cloud.zone";
    masters { 10.2.1.10; };
};

# Forward AWS services
zone "amazonaws.com" IN {
    type forward;
    forward only;
    forwarders { 10.1.0.2; };
};
EOF


Update DHCP Options with both DNS servers:

bash
aws ec2 create-dhcp-options \
  --dhcp-configurations \
    "Key=domain-name,Values=example.cloud" \
    "Key=domain-name-servers,Values=10.2.1.10,10.2.1.11" \
  --region ap-southeast-1


Additional cost: $15.18/month for secondary DNS server

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Automation: Dynamic DNS Updates

### Script to Auto-Register EC2 Instances

bash
#!/bin/bash
# auto-register-dns.sh
# Run via Lambda or cron to auto-update DNS

DNS_SERVER="10.2.1.10"
ZONE_FILE="/var/named/example.cloud.zone"

# Get all running instances in VPC A
INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=vpc-id,Values=$VPC_A_ID" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],PrivateIpAddress]' \
  --output text \
  --region ap-southeast-1)

# SSH to DNS server and update
ssh ec2-user@$DNS_SERVER << 'ENDSSH'
# Backup zone file
sudo cp $ZONE_FILE ${ZONE_FILE}.bak

# Clear old records (keep SOA and NS)
sudo sed -i '/^[a-z]/d' $ZONE_FILE

# Add new records
while read name ip; do
  hostname=$(echo $name | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  echo "${hostname}    IN  A       ${ip}" | sudo tee -a $ZONE_FILE
done

# Increment serial
SERIAL=$(date +%Y%m%d%H)
sudo sed -i "s/[0-9]\{10\}/${SERIAL}/" $ZONE_FILE

# Reload
sudo rndc reload example.cloud
ENDSSH


Run via cron every 5 minutes:
bash
*/5 * * * * /usr/local/bin/auto-register-dns.sh


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Testing the Updated Setup

### Test 1: Verify DNS Server is Used

bash
# SSH to EC2 in VPC A
cat /etc/resolv.conf

# Expected output:
# nameserver 10.2.1.10


### Test 2: Cloud to On-Premise Resolution

bash
# From EC2 in VPC A
dig app.onprem.local

# Expected: 10.2.1.20
# Query should go directly to 10.2.1.10


### Test 3: On-Premise to Cloud Resolution

bash
# From App Server in VPC OP
dig app.example.cloud
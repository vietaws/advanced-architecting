# Scenario 1: All DNS on On-Premises

## Concept

BIND on-premises is the single DNS authority for **both** environments. VPC A is configured via custom DHCP options to use BIND as its DNS server. BIND holds authoritative zones for both `op.viet.vn` and `cloud.viet.vn`, and conditionally forwards AWS service queries back to the VPC A built-in resolver (`10.1.0.2`) to avoid breaking S3, EC2 metadata, and other AWS-managed endpoints.

```
EC2-Cloud queries app.cloud.viet.vn
  → Custom DHCP → BIND (10.2.1.10) via VPC Peering
  → Authoritative zone: cloud.viet.vn
  → Returns 10.1.0.40  ✓

EC2-Cloud queries app.op.viet.vn
  → Custom DHCP → BIND (10.2.1.10) via VPC Peering
  → Authoritative zone: op.viet.vn
  → Returns 10.2.1.20  ✓

EC2-Cloud queries s3.ap-southeast-1.amazonaws.com
  → Custom DHCP → BIND (10.2.1.10)
  → Conditional forwarder: amazonaws.com → 10.1.0.2
  → VPC A built-in resolver → AWS-managed answer  ✓

App Server queries app.cloud.viet.vn
  → DHCP → BIND (10.2.1.10) (local, same VPC)
  → Authoritative zone: cloud.viet.vn
  → Returns 10.1.0.40  ✓
```

**No Route 53 Resolver Endpoints needed.** The only Route 53 component used is the Private Hosted Zone, and even that is optional in this scenario.

---

## Step 1 — Expand BIND Configuration

BIND already serves `op.viet.vn` from the foundation setup. Add the `cloud.viet.vn` authoritative zone and conditional forwarders for AWS services.

SSH to the DNS Server (`10.2.1.10`) and replace `/etc/named.conf`:

```bash
# Run on DNS Server (10.2.1.10)
sudo tee /etc/named.conf > /dev/null << 'EOF'
options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { none; };
    directory "/var/named";
    allow-query     { 10.0.0.0/8; };
    allow-recursion { 10.0.0.0/8; };
    recursion yes;
    dnssec-validation no;
    querylog yes;
};

logging {
    channel query_log {
        file "/var/log/named/query.log" versions 5 size 10m;
        severity info;
        print-time yes;
        print-category yes;
    };
    category queries { query_log; };
};

# ── Authoritative zones ──────────────────────────────────────────

zone "op.viet.vn" IN {
    type master;
    file "/var/named/op.viet.vn.zone";
    allow-update { none; };
};

zone "cloud.viet.vn" IN {
    type master;
    file "/var/named/cloud.viet.vn.zone";
    allow-update { none; };
};

zone "2.10.in-addr.arpa" IN {
    type master;
    file "/var/named/10.2.rev";
    allow-update { none; };
};

zone "1.10.in-addr.arpa" IN {
    type master;
    file "/var/named/10.1.rev";
    allow-update { none; };
};

# ── Conditional forwarders for AWS-managed domains ───────────────
# IMPORTANT: without these, AWS service APIs (S3, EC2, SSM, etc.)
# break for EC2-Cloud because BIND has no records for them.

zone "amazonaws.com" IN {
    type forward;
    forward only;
    forwarders { 10.2.0.2; 8.8.8.8; };
};

zone "ap-southeast-1.compute.internal" IN {
    type forward;
    forward only;
    forwarders { 10.2.0.2; 8.8.8.8; };
};

zone "s3.ap-southeast-1.amazonaws.com" IN {
    type forward;
    forward only;
    forwarders { 10.2.0.2; 8.8.8.8; };
};

# Internet fallback
zone "." IN {
    type forward;
    forward first;
    forwarders { 8.8.8.8; 1.1.1.1; };
};
EOF

sudo mkdir -p /var/log/named
sudo chown named:named /var/log/named
```

## Step 2 — Create Zone File for cloud.viet.vn

```bash
# Run on DNS Server (10.2.1.10)
sudo tee /var/named/cloud.viet.vn.zone > /dev/null << 'EOF'
$TTL 300
@   IN  SOA dns.op.viet.vn. admin.op.viet.vn. (
        2026080401 3600 1800 604800 300 )
@       IN  NS  dns.op.viet.vn.
app     IN  A   10.1.0.40
db      IN  A   10.1.0.50
api     IN  CNAME app.cloud.viet.vn.
EOF

sudo tee /var/named/10.1.rev > /dev/null << 'EOF'
$TTL 300
@   IN  SOA dns.op.viet.vn. admin.op.viet.vn. (
        2026080401 3600 1800 604800 300 )
@   IN  NS  dns.op.viet.vn.
40  IN  PTR app.cloud.viet.vn.
50  IN  PTR db.cloud.viet.vn.
EOF

sudo chown named:named /var/named/cloud.viet.vn.zone /var/named/10.1.rev

sudo tee /var/named/10.2.rev << 'EOF'
$TTL 300
@   IN  SOA dns.op.viet.vn. admin.op.viet.vn. (
              2026080401 3600 1800 604800 300 )
  
@   IN  NS  dns.op.viet.vn.
  
; PTR records — format: <third-octet>.<fourth-octet>
1.10  IN  PTR dns.op.viet.vn.
1.20  IN  PTR app.op.viet.vn.
1.30  IN  PTR db.op.viet.vn.
EOF

sudo chown named:named /var/named/cloud.viet.vn.zone /var/named/10.1.rev
sudo chown named:named /var/named/op.viet.vn.zone /var/named/10.2.rev


# Validate and reload
sudo named-checkconf /etc/named.conf
sudo named-checkzone cloud.viet.vn /var/named/cloud.viet.vn.zone
sudo named-checkzone op.viet.vn /var/named/op.viet.vn.zone
sudo systemctl restart named
sudo systemctl status named
```

## Step 3 — Configure Custom DHCP Options for VPC A

This overrides the default `AmazonProvidedDNS` for VPC A, directing all EC2 DNS queries to BIND.

```bash
DHCP_OPT_ID=$(aws ec2 create-dhcp-options \
  --dhcp-configurations \
    "Key=domain-name,Values=cloud.viet.vn" \
    "Key=domain-name-servers,Values=10.2.1.10" \
  --tag-specifications 'ResourceType=dhcp-options,Tags=[{Key=Name,Value=DHCP-OnPrem-DNS}]' \
  --region ap-southeast-1 \
  --query 'DhcpOptions.DhcpOptionsId' --output text)

aws ec2 associate-dhcp-options \
  --dhcp-options-id $DHCP_OPT_ID \
  --vpc-id $VPC_A_ID \
  --region ap-southeast-1

echo "DHCP Options: $DHCP_OPT_ID"
```

> **Note:** Existing EC2 instances need to renew their DHCP lease before the new DNS server takes effect. Either reboot or run `sudo dhclient -r && sudo dhclient` on each instance.

```bash
# On EC2-Cloud: renew DHCP lease without reboot
sudo dhclient -r && sudo dhclient

# Confirm new DNS server is active
cat /etc/resolv.conf
# Expected: nameserver 10.2.1.10
```

## Step 4 — (Optional) Configure VPC OP DHCP to Also Use BIND

VPC OP by default uses `10.2.0.2` (AmazonProvidedDNS). For EC2s in VPC OP to also use BIND directly, set a custom DHCP there too.

```bash
DHCP_OP_ID=$(aws ec2 create-dhcp-options \
  --dhcp-configurations \
    "Key=domain-name,Values=op.viet.vn" \
    "Key=domain-name-servers,Values=10.2.1.10" \
  --tag-specifications 'ResourceType=dhcp-options,Tags=[{Key=Name,Value=DHCP-CorpLocal}]' \
  --region ap-southeast-1 \
  --query 'DhcpOptions.DhcpOptionsId' --output text)

aws ec2 associate-dhcp-options \
  --dhcp-options-id $DHCP_OP_ID \
  --vpc-id $VPC_OP_ID \
  --region ap-southeast-1
```

---

## Demo Verification

```bash
# ── From EC2-Cloud (10.1.0.40) ───────────────────────────────────

# Confirm DNS server is BIND on-prem
cat /etc/resolv.conf
# nameserver 10.2.1.10

# Cloud → Cloud: BIND answers from cloud.viet.vn zone
dig app.cloud.viet.vn
# Expected: 10.1.0.40

dig api.cloud.viet.vn
# Expected: CNAME → app.cloud.viet.vn → 10.1.0.40

# Cloud → On-prem: BIND answers from op.viet.vn zone
dig app.op.viet.vn
# Expected: 10.2.1.20

dig db.op.viet.vn
# Expected: 10.2.1.30

# AWS services: conditional forwarder kicks in → 10.1.0.2 answers
dig s3.ap-southeast-1.amazonaws.com
# Expected: AWS-managed IPs (not NXDOMAIN)

aws s3 ls --region ap-southeast-1
# Expected: bucket listing works via S3 Gateway Endpoint


# ── From App Server (10.2.1.20) ──────────────────────────────────

dig app.op.viet.vn
# Expected: 10.2.1.20

dig app.cloud.viet.vn
# Expected: 10.1.0.40


# ── Live query log on DNS Server ─────────────────────────────────
sudo tail -f /var/log/named/query.log
# Shows every query flowing through BIND: source IP, query name, type
```

---

**Notes:** Try to stop named service to see the impacts.
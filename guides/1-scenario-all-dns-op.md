# Scenario 1: All DNS on On-Premises

## Concept

BIND on-premises is the single DNS authority for **both** environments. VPC A is configured via custom DHCP options to use BIND as its DNS server. BIND holds authoritative zones for both `corp.local` and `cloud.corp.local`, and conditionally forwards AWS service queries back to the VPC A built-in resolver (`10.1.0.2`) to avoid breaking S3, EC2 metadata, and other AWS-managed endpoints.

```
EC2-Cloud queries app.cloud.corp.local
  → Custom DHCP → BIND (10.2.1.10) via VPC Peering
  → Authoritative zone: cloud.corp.local
  → Returns 10.1.1.50  ✓

EC2-Cloud queries app.corp.local
  → Custom DHCP → BIND (10.2.1.10) via VPC Peering
  → Authoritative zone: corp.local
  → Returns 10.2.1.20  ✓

EC2-Cloud queries s3.ap-southeast-1.amazonaws.com
  → Custom DHCP → BIND (10.2.1.10)
  → Conditional forwarder: amazonaws.com → 10.1.0.2
  → VPC A built-in resolver → AWS-managed answer  ✓

App Server queries app.cloud.corp.local
  → DHCP → BIND (10.2.1.10) (local, same VPC)
  → Authoritative zone: cloud.corp.local
  → Returns 10.1.1.50  ✓
```

**No Route 53 Resolver Endpoints needed.** The only Route 53 component used is the Private Hosted Zone, and even that is optional in this scenario.

**Prerequisite:** Foundation infrastructure from `3-scenario-split-dns.md` (Part 1) is deployed and BIND is running at `10.2.1.10`.

---

## Step 1 — Expand BIND Configuration

BIND already serves `corp.local` from the foundation setup. Add the `cloud.corp.local` authoritative zone and conditional forwarders for AWS services.

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

zone "corp.local" IN {
    type master;
    file "/var/named/corp.local.zone";
    allow-update { none; };
};

zone "cloud.corp.local" IN {
    type master;
    file "/var/named/cloud.corp.local.zone";
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

## Step 2 — Create Zone File for cloud.corp.local

```bash
# Run on DNS Server (10.2.1.10)
sudo tee /var/named/cloud.corp.local.zone > /dev/null << 'EOF'
$TTL 300
@   IN  SOA dns.corp.local. admin.corp.local. (
        2026080401 3600 1800 604800 300 )
@       IN  NS  dns.corp.local.
app     IN  A   10.1.1.50
web     IN  A   10.1.1.51
api     IN  CNAME app.cloud.corp.local.
EOF

sudo tee /var/named/10.1.rev > /dev/null << 'EOF'
$TTL 300
@   IN  SOA dns.corp.local. admin.corp.local. (
        2026080401 3600 1800 604800 300 )
@   IN  NS  dns.corp.local.
50  IN  PTR app.cloud.corp.local.
51  IN  PTR web.cloud.corp.local.
EOF

sudo chown named:named /var/named/cloud.corp.local.zone /var/named/10.1.rev

# Validate and reload
sudo named-checkconf /etc/named.conf
sudo named-checkzone cloud.corp.local /var/named/cloud.corp.local.zone
sudo named-checkzone corp.local /var/named/corp.local.zone
sudo systemctl restart named
sudo systemctl status named
```

## Step 3 — Configure Custom DHCP Options for VPC A

This overrides the default `AmazonProvidedDNS` for VPC A, directing all EC2 DNS queries to BIND.

```bash
DHCP_OPT_ID=$(aws ec2 create-dhcp-options \
  --dhcp-configurations \
    "Key=domain-name,Values=cloud.corp.local" \
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
    "Key=domain-name,Values=corp.local" \
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
# ── From EC2-Cloud (10.1.1.50) ───────────────────────────────────

# Confirm DNS server is BIND on-prem
cat /etc/resolv.conf
# nameserver 10.2.1.10

# Cloud → Cloud: BIND answers from cloud.corp.local zone
dig app.cloud.corp.local
# Expected: 10.1.1.50

dig api.cloud.corp.local
# Expected: CNAME → app.cloud.corp.local → 10.1.1.50

# Cloud → On-prem: BIND answers from corp.local zone
dig app.corp.local
# Expected: 10.2.1.20

dig db.corp.local
# Expected: 10.2.1.30

# AWS services: conditional forwarder kicks in → 10.1.0.2 answers
dig s3.ap-southeast-1.amazonaws.com
# Expected: AWS-managed IPs (not NXDOMAIN)

aws s3 ls --region ap-southeast-1
# Expected: bucket listing works via S3 Gateway Endpoint


# ── From App Server (10.2.1.20) ──────────────────────────────────

dig app.corp.local
# Expected: 10.2.1.20

dig app.cloud.corp.local
# Expected: 10.1.1.50


# ── Live query log on DNS Server ─────────────────────────────────
sudo tail -f /var/log/named/query.log
# Shows every query flowing through BIND: source IP, query name, type
```

---

## Blast Radius Test (Key Demo Moment)

```bash
# 1. Stop BIND
sudo systemctl stop named    # on DNS Server

# 2. From EC2-Cloud
dig app.cloud.corp.local         # ✗ times out
dig app.corp.local           # ✗ times out
aws s3 ls                    # ✗ fails (S3 DNS broken too)

# 3. From App Server
dig app.cloud.corp.local         # ✗ times out
dig app.corp.local           # ✗ times out

# 4. Restart BIND → full recovery
sudo systemctl start named
dig app.cloud.corp.local         # ✓ 10.1.1.50
```

**Talking point:** BIND is a single point of failure for both environments. In production this requires HA (primary + secondary BIND) or adding `10.2.1.11` as a secondary DNS server and listing both IPs in the DHCP options. Compare this to Split DNS (Scenario 3) where a BIND failure only affects `corp.local`.

---

## Cleanup: Restore Default DHCP Before Next Scenario

When transitioning to Scenario 1 (All DNS on AWS), restore VPC A to use `AmazonProvidedDNS`:

```bash
# Get the default DHCP options ID for the region
DEFAULT_DHCP="default"

aws ec2 associate-dhcp-options \
  --dhcp-options-id $DEFAULT_DHCP \
  --vpc-id $VPC_A_ID \
  --region ap-southeast-1

# Renew DHCP on EC2-Cloud
# sudo dhclient -r && sudo dhclient
```

---

## Cost (All DNS on On-Premises)

| Component | Details | Monthly |
|-----------|---------|---------|
| EC2 t3.micro (DNS Server) | Already deployed in foundation | $7.59 |
| PHZ `cloud.corp.local` (optional) | Not required for this scenario | $0 |
| Route 53 Resolver Endpoints | None needed | $0 |
| Resolver Rules | None needed | $0 |
| **Route 53 total** | | **$0** |
| **Total incremental** | vs. base infra | **$0/month** |

This is the cheapest scenario by far. The cost driver is the EC2 DNS server itself, which is already part of the base infrastructure.

The hidden cost is operational: every IP change on EC2-Cloud requires a manual zone file update and `rndc reload` on BIND.

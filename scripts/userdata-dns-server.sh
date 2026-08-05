#!/bin/bash
# =============================================================================
# Hybrid DNS Demo — DNS Server (BIND)
# VPC OP | IP: 10.2.1.10 | Hostname: dns.op.viet.vn
#
# This script is used as EC2 user-data. It installs BIND and configures it
# as the authoritative DNS server for op.viet.vn (on-premises zone).
#
# The forwarder section is intentionally left pointing to 10.1.0.2 (VPC A
# built-in resolver) as a safe default. Each demo scenario will SSH in and
# swap /etc/named.conf for the scenario-specific config:
#
#   Scenario 1 (All AWS)  : BIND forwards everything to Inbound Endpoint
#   Scenario 2 (All On-prem): BIND authoritative for both zones
#   Scenario 3 (Split DNS): BIND authoritative for op.viet.vn only,
#                            forwards cloud.viet.vn to Inbound Endpoint
#
# After first boot, verify with:
#   systemctl status named
#   dig @10.2.1.10 app.op.viet.vn       # should return 10.2.1.20
#   dig @10.2.1.10 db.op.viet.vn        # should return 10.2.1.30
# =============================================================================

set -euo pipefail
exec > >(tee /var/log/userdata-dns-server.log) 2>&1

echo "[$(date)] Starting DNS Server setup..."

# ── 1. System update & BIND install ──────────────────────────────────────────
dnf update -y
dnf install -y bind bind-utils

# ── 2. named.conf — base config (authoritative for op.viet.vn) ───────────────
cat > /etc/named.conf << 'EOF'
options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { none; };
    directory "/var/named";
    dump-file "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";

    # Accept queries from both VPCs
    allow-query     { 10.0.0.0/8; };
    allow-recursion { 10.0.0.0/8; };
    recursion yes;
    dnssec-validation no;
    querylog yes;

    # Default: forward unknown queries to VPC A resolver (safe for AWS services)
    # Replaced per-scenario during the demo
    forwarders { 10.2.0.2; 8.8.8.8; };
    forward first;
};

logging {
    channel default_log {
        file "/var/log/named/named.log" versions 5 size 20m;
        severity info;
        print-time yes;
        print-severity yes;
    };
    channel query_log {
        file "/var/log/named/query.log" versions 5 size 20m;
        severity info;
        print-time yes;
        print-category yes;
    };
    category default  { default_log; };
    category queries  { query_log;   };
};

# ── On-premises authoritative zone ───────────────────────────────────────────
zone "op.viet.vn" IN {
    type master;
    file "/var/named/op.viet.vn.zone";
    allow-update { none; };
    allow-transfer { none; };
};

# ── Reverse zone for VPC OP (10.2.x.x) ───────────────────────────────────────
zone "1.2.10.in-addr.arpa" IN {
    type master;
    file "/var/named/10.2.1.rev";
    allow-update { none; };
};
EOF

# ── 3. op.viet.vn forward zone ───────────────────────────────────────────────
cat > /var/named/op.viet.vn.zone << 'EOF'
$TTL 300
@   IN  SOA dns.op.viet.vn. admin.op.viet.vn. (
            2026080401  ; serial (YYYYMMDDNN)
            3600        ; refresh
            1800        ; retry
            604800      ; expire
            300 )       ; minimum TTL

; Name servers
@       IN  NS      dns.op.viet.vn.

; A records — on-premises hosts
dns     IN  A       10.2.1.10
app     IN  A       10.2.1.20
db      IN  A       10.2.1.30
EOF

# ── 4. Reverse zone for 10.2.1.0/24 ──────────────────────────────────────────
cat > /var/named/10.2.1.rev << 'EOF'
$TTL 300
@   IN  SOA dns.op.viet.vn. admin.op.viet.vn. (
            2026080401 3600 1800 604800 300 )

@   IN  NS  dns.op.viet.vn.

; PTR records
10  IN  PTR dns.op.viet.vn.
20  IN  PTR app.op.viet.vn.
30  IN  PTR db.op.viet.vn.
EOF

# ── 5. Permissions & log directory ───────────────────────────────────────────
mkdir -p /var/log/named /var/named/data
chown -R named:named /var/named /var/log/named

# ── 6. Validate config ───────────────────────────────────────────────────────
named-checkconf /etc/named.conf
named-checkzone op.viet.vn /var/named/op.viet.vn.zone
named-checkzone 1.2.10.in-addr.arpa /var/named/10.2.1.rev

# ── 7. Start BIND ────────────────────────────────────────────────────────────
systemctl enable named
systemctl start named

# ── 8. Install dig / nslookup tools for demo testing ─────────────────────────
dnf install -y bind-utils

# ── 9. Set hostname ──────────────────────────────────────────────────────────
hostnamectl set-hostname dns.op.viet.vn

echo "[$(date)] DNS Server setup complete."
echo "Test: dig @10.2.1.10 app.op.viet.vn"
echo "Test: dig @10.2.1.10 db.op.viet.vn"

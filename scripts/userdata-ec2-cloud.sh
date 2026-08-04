#!/bin/bash
# =============================================================================
# Hybrid DNS Demo — EC2 Cloud App Server
# VPC A | IP: 10.1.1.50 | Hostname: app.cloud.corp.local
#
# Simulates a cloud-hosted application. Runs a simple HTTP server so that
# on-premises servers can test connectivity in both directions.
# Also pre-installs all tools needed for DNS testing during the demo.
#
# After first boot, verify with:
#   curl http://10.1.1.50              # direct IP
#   curl http://app.cloud.corp.local   # via DNS (after scenario configured)
#   aws s3 ls --region ap-southeast-1  # S3 via gateway endpoint
# =============================================================================

set -euo pipefail
exec > >(tee /var/log/userdata-ec2-cloud.log) 2>&1

echo "[$(date)] Starting EC2-Cloud setup..."

# ── 1. System update ─────────────────────────────────────────────────────────
dnf update -y
dnf install -y bind-utils nc python3 postgresql15 awscli

# ── 2. Set hostname ──────────────────────────────────────────────────────────
hostnamectl set-hostname app.cloud.corp.local

# ── 3. Simple HTTP server ─────────────────────────────────────────────────────
mkdir -p /var/www/app

cat > /var/www/app/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Cloud App Server</title></head>
<body>
  <h1>Cloud App Server</h1>
  <p><strong>Hostname:</strong> app.cloud.corp.local</p>
  <p><strong>IP:</strong> 10.1.1.50</p>
  <p><strong>Environment:</strong> VPC A (AWS Cloud, ap-southeast-1)</p>
  <p>If you can reach this page from the on-premises app server, hybrid DNS and routing are working correctly.</p>
</body>
</html>
EOF

cat > /etc/systemd/system/demo-app.service << 'EOF'
[Unit]
Description=Hybrid DNS Demo Cloud App (HTTP)
After=network.target

[Service]
Type=simple
WorkingDirectory=/var/www/app
ExecStart=/usr/bin/python3 -m http.server 80
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable demo-app
systemctl start demo-app

# ── 4. DNS + connectivity test helper ────────────────────────────────────────
cat > /usr/local/bin/dns-test << 'SCRIPT'
#!/bin/bash
echo "============================================"
echo " DNS Test — app.cloud.corp.local (10.1.1.50)"
echo "============================================"
echo ""
echo "-- Cloud records (Route 53 PHZ) --"
dig +short app.cloud.corp.local
dig +short web.cloud.corp.local
echo ""
echo "-- On-prem records (via Resolver or BIND) --"
dig +short app.corp.local
dig +short db.corp.local
dig +short dns.corp.local
echo ""
echo "-- AWS service DNS --"
echo -n "S3 endpoint: "
dig +short s3.ap-southeast-1.amazonaws.com | head -2
echo ""
echo "-- Connectivity tests --"
echo -n "HTTP to app.corp.local:    "
curl -s --connect-timeout 3 -o /dev/null -w "%{http_code}" http://app.corp.local || echo "FAIL"
echo ""
echo -n "PostgreSQL to db.corp.local: "
nc -zv -w 3 db.corp.local 5432 2>&1 | grep -o "succeeded\|failed\|timed out" || echo "FAIL"
echo ""
echo "-- S3 access via gateway endpoint --"
aws s3 ls --region ap-southeast-1 2>&1 | head -5
SCRIPT

chmod +x /usr/local/bin/dns-test

# ── 5. DB connectivity helper ─────────────────────────────────────────────────
cat > /usr/local/bin/db-test << 'SCRIPT'
#!/bin/bash
echo "Testing PostgreSQL connection to db.corp.local:5432 ..."
PGPASSWORD=DemoPassword psql -h db.corp.local -U dbadmin -d demo \
    -c "SELECT * FROM products;" \
    && echo "SUCCESS" \
    || echo "FAILED — check DNS and security group rules"
SCRIPT

chmod +x /usr/local/bin/db-test

echo "[$(date)] EC2-Cloud setup complete."
echo "HTTP server running on port 80."
echo "Run 'dns-test' to verify DNS resolution."
echo "Run 'db-test' to test MySQL connectivity to on-prem DB."

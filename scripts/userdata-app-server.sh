#!/bin/bash
# =============================================================================
# Hybrid DNS Demo — On-Premises App Server
# VPC OP | IP: 10.2.1.20 | Hostname: app.corp.local
#
# Simulates an on-premises application server. Runs a simple HTTP server
# so cross-environment connectivity can be tested end-to-end (DNS + TCP).
#
# After first boot, verify with:
#   curl http://10.2.1.20        # direct IP — should work immediately
#   curl http://app.corp.local   # DNS — works after DNS scenario is configured
# =============================================================================

set -euo pipefail
exec > >(tee /var/log/userdata-app-server.log) 2>&1

echo "[$(date)] Starting App Server (on-prem) setup..."

# ── 1. System update ─────────────────────────────────────────────────────────
dnf update -y
dnf install -y bind-utils nc python3

# ── 2. Set hostname ──────────────────────────────────────────────────────────
hostnamectl set-hostname app.corp.local

# ── 3. Simple HTTP server (Python) ───────────────────────────────────────────
# Serves a plain-text page identifying this host — useful for demo curl tests
mkdir -p /var/www/app

cat > /var/www/app/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>On-Prem App Server</title></head>
<body>
  <h1>On-Premises App Server</h1>
  <p><strong>Hostname:</strong> app.corp.local</p>
  <p><strong>IP:</strong> 10.2.1.20</p>
  <p><strong>Environment:</strong> VPC OP (simulated on-premises)</p>
  <p>If you can reach this page from EC2-Cloud, hybrid DNS and routing are working correctly.</p>
</body>
</html>
EOF

# Create systemd service for the HTTP server
cat > /etc/systemd/system/demo-app.service << 'EOF'
[Unit]
Description=Hybrid DNS Demo App Server (HTTP)
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

# ── 4. DNS testing helpers ────────────────────────────────────────────────────
# Script to quickly run all DNS resolution tests from this host
cat > /usr/local/bin/dns-test << 'SCRIPT'
#!/bin/bash
echo "============================================"
echo " DNS Test — app.corp.local (10.2.1.20)"
echo "============================================"
echo ""
echo "-- Current DNS server --"
grep nameserver /etc/resolv.conf
echo ""
echo "-- On-prem records (via BIND directly @ 10.2.1.10) --"
dig @10.2.1.10 +noall +answer app.corp.local
dig @10.2.1.10 +noall +answer db.corp.local
dig @10.2.1.10 +noall +answer dns.corp.local
echo ""
echo "-- On-prem records (via configured DNS) --"
dig +noall +answer app.corp.local
dig +noall +answer db.corp.local
echo ""
echo "-- Cloud records (via configured DNS) --"
dig +noall +answer app.cloud.corp.local
echo ""
echo "-- Connectivity to EC2-Cloud (direct IP) --"
curl -sf --connect-timeout 3 http://10.1.1.50/ || echo "Not reachable via IP"
SCRIPT

chmod +x /usr/local/bin/dns-test

echo "[$(date)] App Server setup complete."
echo "HTTP server running on port 80."
echo "Run 'dns-test' to verify DNS resolution from this host."

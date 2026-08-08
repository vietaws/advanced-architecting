#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/op-app-setup.log | logger -t op-app-setup) 2>&1

# ---------------------------------------------------------------------------
# 0. Configuration — edit before launching
# ---------------------------------------------------------------------------
# NFS & SMB server IPs must be reachable from this EC2 instance (op-app)
NFS_SERVER_IP="NFS_SERVER_PRIVATE_IP"      # e.g. 10.1.1.10
NFS_EXPORT="/data/nfs"
SMB_SERVER_IP="SMB_SERVER_PRIVATE_IP"      # e.g. 10.1.1.20  OR SGW appliance private IP
SMB_SHARE="smb"                            # share name on op-smb-server OR SGW console
SMB_USER="guest"                           # guest for op-smb-server; guest for SGW too
SMB_PASSWORD=""                            # empty = local guest (no password)
                                           # set to e.g. "Passw0rd123" for SGW guest access

# Local Settings for OP-APP - DONT CHANGE UNLESS YOU KNOW WHAT YOU ARE DOING
NFS_MOUNT="/mnt/nfs"
SMB_MOUNT="/mnt/smb"
REGION="us-east-1"
APP_DIR="/opt/app"
APP_USER="webapp"
GITHUB_REPO="https://github.com/vietaws/architecting-pro.git"
GITHUB_BRANCH="sgw-vs-datasync"

echo "=== Starting op-app setup ==="
echo "NFS_SERVER : $NFS_SERVER_IP"
echo "SMB_SERVER : $SMB_SERVER_IP"

# ---------------------------------------------------------------------------
# 1. System update and base packages
# ---------------------------------------------------------------------------
dnf update -y
dnf install -y \
  nfs-utils \
  cifs-utils \
  git

# ---------------------------------------------------------------------------
# 2. Install Node.js 24 LTS via native dnf (Amazon Linux 2023 built-in repo)
# ---------------------------------------------------------------------------
dnf install -y nodejs24

node --version
npm  --version

# ---------------------------------------------------------------------------
# 3. Create app user FIRST — uid required for CIFS mount options below
# ---------------------------------------------------------------------------
id "$APP_USER" &>/dev/null || useradd -r -s /sbin/nologin "$APP_USER"
WEBAPP_UID=$(id -u "$APP_USER")
WEBAPP_GID=$(id -g "$APP_USER")
echo "webapp uid=${WEBAPP_UID} gid=${WEBAPP_GID}"

# ---------------------------------------------------------------------------
# 4. Mount NFS share
# ---------------------------------------------------------------------------
mkdir -p "$NFS_MOUNT"

if ! grep -q "$NFS_SERVER_IP" /etc/fstab; then
  echo "${NFS_SERVER_IP}:${NFS_EXPORT} ${NFS_MOUNT} nfs _netdev,vers=4,hard,intr 0 0" >> /etc/fstab
fi

NFS_MOUNTED=false
for i in $(seq 1 6); do
  if mount -t nfs -o vers=4,hard,intr "${NFS_SERVER_IP}:${NFS_EXPORT}" "$NFS_MOUNT"; then
    echo "NFS mounted successfully"
    NFS_MOUNTED=true
    break
  fi
  echo "NFS mount attempt $i failed, retrying in 5s..."
  sleep 5
done
$NFS_MOUNTED || echo "WARNING: NFS mount failed — app will start but NFS tab will be empty"

# ---------------------------------------------------------------------------
# 5. Mount SMB share
#    SMB_PASSWORD empty  → local guest (no password, op-smb-server)
#    SMB_PASSWORD set    → guest with password (SGW File Gateway)
# ---------------------------------------------------------------------------
mkdir -p "$SMB_MOUNT"

if [[ -z "$SMB_PASSWORD" ]]; then
  SMB_OPTS="guest,uid=${WEBAPP_UID},gid=${WEBAPP_GID},file_mode=0777,dir_mode=0777,vers=3.0,iocharset=utf8"
  echo "SMB mode: local guest (no password)"
else
  # Write credentials file — keeps password out of fstab and mount output
  # SGW guest access uses "smbguest" as the internal account name
  cat > /etc/smb-credentials << CREDS
username=smbguest
password=${SMB_PASSWORD}
CREDS
  chmod 600 /etc/smb-credentials
  SMB_OPTS="credentials=/etc/smb-credentials,sec=ntlmsspi,uid=${WEBAPP_UID},gid=${WEBAPP_GID},file_mode=0777,dir_mode=0777"
  echo "SMB mode: authenticated via SGW guest (smbguest)"
fi

if ! grep -q "$SMB_SERVER_IP" /etc/fstab; then
  echo "//${SMB_SERVER_IP}/${SMB_SHARE} ${SMB_MOUNT} cifs _netdev,${SMB_OPTS} 0 0" >> /etc/fstab
fi

SMB_MOUNTED=false
for i in $(seq 1 6); do
  if mount -t cifs -o "${SMB_OPTS}" "//${SMB_SERVER_IP}/${SMB_SHARE}" "$SMB_MOUNT"; then
    echo "SMB mounted successfully"
    SMB_MOUNTED=true
    break
  fi
  echo "SMB mount attempt $i failed, retrying in 5s..."
  sleep 5
done
$SMB_MOUNTED || echo "WARNING: SMB mount failed — app will start but SMB tab will be empty"

# ---------------------------------------------------------------------------
# 6. Clone app from GitHub and install dependencies
# ---------------------------------------------------------------------------
git clone --branch "$GITHUB_BRANCH" --depth 1 "$GITHUB_REPO" /tmp/repo
cp -r /tmp/repo/op-app "$APP_DIR"
rm -rf /tmp/repo

cd "$APP_DIR"
npm install --omit=dev --no-audit --no-fund
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

# ---------------------------------------------------------------------------
# 7. Write .env file and create systemd service
# ---------------------------------------------------------------------------
cat > "$APP_DIR/.env" << ENV
PORT=80
NFS_MOUNT=${NFS_MOUNT}
SMB_MOUNT=${SMB_MOUNT}
ENV

chmod 640 "$APP_DIR/.env"
chown root:"$APP_USER" "$APP_DIR/.env"

cat > /etc/systemd/system/demo-app.service << SYSTEMD
[Unit]
Description=OP Demo Image Viewer (NFS + SMB)
After=network-online.target remote-fs.target
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/node $APP_DIR/server.js
Restart=on-failure
RestartSec=5

EnvironmentFile=$APP_DIR/.env

AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SYSTEMD

# ---------------------------------------------------------------------------
# 8. Enable and start the service
# ---------------------------------------------------------------------------
systemctl daemon-reload
systemctl enable demo-app
systemctl start  demo-app

# ---------------------------------------------------------------------------
# 9. Verify
# ---------------------------------------------------------------------------
sleep 3
systemctl is-active demo-app && \
  echo "=== demo-app is RUNNING ===" || \
  echo "=== ERROR: demo-app failed — check: journalctl -u demo-app ==="

echo "=== Mounts ===" && df -h | grep -E "nfs|cifs|smb|Filesystem" || true
echo "=== Setup complete. Access at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4) ==="

# ---------------------------------------------------------------------------
# HOW TO SWITCH SMB MOUNT DURING DEMO (run on op-app via SSM)
#
# Phase 1 — op-smb-server (local guest, no password):
#   SMB_SERVER_IP=<op-smb-server-private-ip>
#   SMB_SHARE=smb
#   SMB_OPTS="guest,uid=$(id -u webapp),gid=$(id -g webapp),file_mode=0777,dir_mode=0777,vers=3.0"
#
# Phase 2 — SGW File Gateway (guest with password):
#   SMB_SERVER_IP=<sgw-appliance-private-ip>
#   SMB_SHARE=<share-name-from-sgw-console>
#   cat > /etc/smb-credentials << EOF
#   username=smbguest
#   password=Passw0rd123
#   EOF
#   chmod 600 /etc/smb-credentials
#   SMB_OPTS="credentials=/etc/smb-credentials,sec=ntlmsspi,uid=$(id -u webapp),gid=$(id -g webapp),file_mode=0777,dir_mode=0777"
#
# Switch command (same for both phases):
#   umount /mnt/smb
#   mount -t cifs -o "${SMB_OPTS}" "//${SMB_SERVER_IP}/${SMB_SHARE}" /mnt/smb
#   df -h /mnt/smb && ls /mnt/smb
# ---------------------------------------------------------------------------

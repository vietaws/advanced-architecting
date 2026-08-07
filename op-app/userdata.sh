#!/bin/bash
# =============================================================================
# op-app userdata.sh
# EC2 User Data — OP App Server (t4g.micro, Amazon Linux 2023, ARM64)
# Mounts NFS + SMB shares, clones app from GitHub, runs on port 80
#
# FILL IN before launching the EC2 instance:
#   NFS_SERVER_IP — private IP of op-nfs-server (e.g. 10.1.1.x)
#   SMB_SERVER_IP — private IP of op-smb-server (e.g. 10.1.1.x)
# =============================================================================
set -euo pipefail
exec > >(tee /var/log/op-app-setup.log | logger -t op-app-setup) 2>&1

# ---------------------------------------------------------------------------
# 0. Configuration — edit NFS_SERVER_IP and SMB_SERVER_IP before launching
# ---------------------------------------------------------------------------
NFS_SERVER_IP="<NFS_SERVER_PRIVATE_IP>"    # e.g. 10.1.1.10
NFS_EXPORT="/data/nfs"
SMB_SERVER_IP="<SMB_SERVER_PRIVATE_IP>"    # e.g. 10.1.1.20
SMB_SHARE="smb"
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
# 5. Mount SMB share (guest access, no password)
#    Use numeric uid/gid so CIFS kernel module resolves correctly
# ---------------------------------------------------------------------------
mkdir -p "$SMB_MOUNT"

if ! grep -q "$SMB_SERVER_IP" /etc/fstab; then
  echo "//${SMB_SERVER_IP}/${SMB_SHARE} ${SMB_MOUNT} cifs _netdev,guest,uid=${WEBAPP_UID},gid=${WEBAPP_GID},file_mode=0777,dir_mode=0777,vers=3.0,iocharset=utf8 0 0" >> /etc/fstab
fi

SMB_MOUNTED=false
for i in $(seq 1 6); do
  if mount -t cifs \
    -o "guest,uid=${WEBAPP_UID},gid=${WEBAPP_GID},file_mode=0777,dir_mode=0777,vers=3.0,iocharset=utf8" \
    "//${SMB_SERVER_IP}/${SMB_SHARE}" "$SMB_MOUNT"; then
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

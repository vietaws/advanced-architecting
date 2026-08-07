#!/bin/bash
# =============================================================================
# cloud-app-userdata.sh
# EC2 User Data — Cloud App Server (t4g.micro, Amazon Linux 2023, ARM64)
# Clones app code from GitHub, mounts EFS, runs demo image viewer on port 80
#
# FILL IN before launching the EC2 instance:
#   EFS_ID — your EFS file system ID (e.g. fs-0abc1234def56789)
# =============================================================================
set -euo pipefail
exec > >(tee /var/log/cloud-app-setup.log | logger -t cloud-app-setup) 2>&1

# ---------------------------------------------------------------------------
# 0. Configuration — edit EFS_ID before launching
# ---------------------------------------------------------------------------
S3_BUCKET="sgw-datasync-demo-$(aws sts get-caller-identity --query Account --output text)"
S3_PREFIX="images/products/"
EFS_ID="<YOUR_EFS_FILE_SYSTEM_ID>"    # e.g. fs-0abc1234def56789
EFS_MOUNT="/mnt/efs"
EFS_SUBDIR="images/products"
REGION="us-east-1"
APP_DIR="/opt/app"
APP_USER="webapp"

GITHUB_REPO="https://github.com/vietaws/architecting-pro.git"
GITHUB_BRANCH="sgw-vs-datasync"

echo "=== Starting cloud-app setup ==="
echo "S3_BUCKET : $S3_BUCKET"
echo "EFS_ID    : $EFS_ID"
echo "REGION    : $REGION"

# ---------------------------------------------------------------------------
# 1. System update and base packages
# ---------------------------------------------------------------------------
dnf update -y
dnf install -y \
  amazon-efs-utils \
  nfs-utils \
  git

# ---------------------------------------------------------------------------
# 2. Install Node.js 24 LTS via native dnf (Amazon Linux 2023 built-in repo)
# ---------------------------------------------------------------------------
dnf install -y nodejs24

node --version
npm  --version

# ---------------------------------------------------------------------------
# 3. Mount EFS
# ---------------------------------------------------------------------------
mkdir -p "$EFS_MOUNT"

if ! grep -q "$EFS_ID" /etc/fstab; then
  echo "${EFS_ID}:/ ${EFS_MOUNT} efs _netdev,tls,iam 0 0" >> /etc/fstab
fi

for i in $(seq 1 6); do
  if mount -t efs -o tls,iam "${EFS_ID}:/" "$EFS_MOUNT"; then
    echo "EFS mounted successfully"
    break
  fi
  echo "EFS mount attempt $i failed, retrying in 5s..."
  sleep 5
done

mkdir -p "${EFS_MOUNT}/${EFS_SUBDIR}"
chmod 755 "${EFS_MOUNT}/${EFS_SUBDIR}"

# ---------------------------------------------------------------------------
# 4. Create app user (no login shell)
# ---------------------------------------------------------------------------
id "$APP_USER" &>/dev/null || useradd -r -s /sbin/nologin "$APP_USER"

# ---------------------------------------------------------------------------
# 5. Clone app from GitHub and install dependencies
# ---------------------------------------------------------------------------
git clone --branch "$GITHUB_BRANCH" --depth 1 "$GITHUB_REPO" /tmp/repo
cp -r /tmp/repo/app "$APP_DIR"
rm -rf /tmp/repo

cd "$APP_DIR"
npm install --omit=dev --no-audit --no-fund
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

# ---------------------------------------------------------------------------
# 6. Write .env file and create systemd service
# ---------------------------------------------------------------------------
cat > "$APP_DIR/.env" << ENV
PORT=80
AWS_REGION=${REGION}
S3_BUCKET=${S3_BUCKET}
S3_PREFIX=${S3_PREFIX}
EFS_MOUNT=${EFS_MOUNT}
EFS_SUBDIR=${EFS_SUBDIR}
ENV

chmod 640 "$APP_DIR/.env"
chown root:"$APP_USER" "$APP_DIR/.env"

cat > /etc/systemd/system/demo-app.service << SYSTEMD
[Unit]
Description=Demo Image Viewer (S3 + EFS)
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
# 7. Enable and start the service
# ---------------------------------------------------------------------------
systemctl daemon-reload
systemctl enable demo-app
systemctl start  demo-app

# ---------------------------------------------------------------------------
# 8. Verify
# ---------------------------------------------------------------------------
sleep 3
systemctl is-active demo-app && \
  echo "=== demo-app is RUNNING ===" || \
  echo "=== ERROR: demo-app failed — check: journalctl -u demo-app ==="

echo "=== Setup complete. Access at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4) ==="

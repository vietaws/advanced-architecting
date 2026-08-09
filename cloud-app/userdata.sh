#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/cloud-app-setup.log | logger -t cloud-app-setup) 2>&1

# ---------------------------------------------------------------------------
# Demo Scenario #1 - DataSync: Cloud App (S3 + EFS) — userdata.sh
# Demo Scenario #2 - Storage Gateway: Cloud App (S3 + EBS) — userdata.sh
# Demo Scenario #3 - Storage Gateway: Cloud App (SGW S3 + SGW SMB) — userdata.sh
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 0. Configuration
# ---------------------------------------------------------------------------
REGION="us-east-1"
S3_BUCKET="sgw-datasync-demo-ACCOUNT_ID"                         # e.g. my-demo-bucket
S3_PREFIX="products/"
STORAGE_MODE="efs"                            # Values: "efs" (Phase 1) or "ebs" (Phase 2)
EFS_ID="EFS_ID"                               # e.g. fs-0abc1234def56789
LOCAL_MOUNT="/mnt/efs"                        # /mnt/efs for Phase 1, /mnt/ebs for Phase 2
LOCAL_SUBDIR="/"
APP_DIR="/opt/app"
APP_USER="webapp"

GITHUB_REPO="https://github.com/vietaws/architecting-pro.git"
GITHUB_BRANCH="sgw-vs-datasync"

echo "=== Starting cloud-app setup ==="
echo "S3_BUCKET    : $S3_BUCKET"
echo "STORAGE_MODE : $STORAGE_MODE"
echo "EFS_ID       : $EFS_ID"

# ---------------------------------------------------------------------------
# 1. System update and base packages
# ---------------------------------------------------------------------------
dnf update -y
dnf install -y \
  amazon-efs-utils \
  nfs-utils \
  git

# ---------------------------------------------------------------------------
# 1a. Build ntfs-3g from source (not in AL2023 default repos for aarch64)
#     Required for Phase 2: mounting NTFS-formatted EBS volume from Volume Gateway snapshot
# ---------------------------------------------------------------------------
dnf install -y gcc make fuse fuse-devel libgcrypt-devel

NTFS3G_VERSION="2022.10.3"
curl -fsSL "https://tuxera.com/opensource/ntfs-3g_ntfsprogs-${NTFS3G_VERSION}.tgz" \
  -o /tmp/ntfs-3g.tgz
tar -xzf /tmp/ntfs-3g.tgz -C /tmp
cd "/tmp/ntfs-3g_ntfsprogs-${NTFS3G_VERSION}"
./configure --prefix=/usr --disable-static 2>&1 | tail -5
make -j"$(nproc)" 2>&1 | tail -5
make install
ldconfig
cd / && rm -rf "/tmp/ntfs-3g_ntfsprogs-${NTFS3G_VERSION}" /tmp/ntfs-3g.tgz
ntfs-3g --version && echo "ntfs-3g installed successfully"

# ---------------------------------------------------------------------------
# 2. Install Node.js 24 LTS
# ---------------------------------------------------------------------------
dnf install -y nodejs24

node --version
npm  --version

# ---------------------------------------------------------------------------
# 3. Create mount point directories (both EFS and EBS upfront)
# ---------------------------------------------------------------------------
mkdir -p /mnt/efs /mnt/ebs

# ---------------------------------------------------------------------------
# 4. Mount EFS (Phase 1 — DataSync demo)
#    Phase 2 (SGW/EBS): EBS volume is attached and mounted manually after
#    Volume Gateway snapshot is created. See 06-commands.md for steps.
# ---------------------------------------------------------------------------
if ! grep -q "$EFS_ID" /etc/fstab; then
  echo "${EFS_ID}:/ /mnt/efs efs _netdev,tls,iam 0 0" >> /etc/fstab
fi

EFS_MOUNTED=false
for i in $(seq 1 6); do
  if mount -t efs -o tls,iam "${EFS_ID}:/" /mnt/efs; then
    echo "EFS mounted successfully"
    EFS_MOUNTED=true
    break
  fi
  echo "EFS mount attempt $i failed, retrying in 5s..."
  sleep 5
done
$EFS_MOUNTED || echo "WARNING: EFS mount failed — app will start but EFS tab will be empty"

mkdir -p "/mnt/efs/${LOCAL_SUBDIR}"
chmod 755 "/mnt/efs/${LOCAL_SUBDIR}"

# ---------------------------------------------------------------------------
# 5. Create app user
# ---------------------------------------------------------------------------
id "$APP_USER" &>/dev/null || useradd -r -s /sbin/nologin "$APP_USER"

# ---------------------------------------------------------------------------
# 6. Clone app from GitHub and install dependencies
# ---------------------------------------------------------------------------
git clone --branch "$GITHUB_BRANCH" --depth 1 "$GITHUB_REPO" /tmp/repo
cp -r /tmp/repo/cloud-app "$APP_DIR"
rm -rf /tmp/repo

cd "$APP_DIR"
npm install --omit=dev --no-audit --no-fund
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

# ---------------------------------------------------------------------------
# 7. Write .env file
# ---------------------------------------------------------------------------
cat > "$APP_DIR/.env" << ENV
PORT=80
AWS_REGION=${REGION}
S3_BUCKET=${S3_BUCKET}
S3_PREFIX=${S3_PREFIX}
STORAGE_MODE=${STORAGE_MODE}
LOCAL_MOUNT=${LOCAL_MOUNT}
LOCAL_SUBDIR=${LOCAL_SUBDIR}
ENV

chmod 640 "$APP_DIR/.env"
chown root:"$APP_USER" "$APP_DIR/.env"

# ---------------------------------------------------------------------------
# 8. Create systemd service
# ---------------------------------------------------------------------------
cat > /etc/systemd/system/demo-app.service << SYSTEMD
[Unit]
Description=Cloud Demo Image Viewer (S3 + EFS/EBS)
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
# 9. Enable and start
# ---------------------------------------------------------------------------
systemctl daemon-reload
systemctl enable demo-app
systemctl start  demo-app

# ---------------------------------------------------------------------------
# 10. Verify
# ---------------------------------------------------------------------------
sleep 3
systemctl is-active demo-app && \
  echo "=== demo-app is RUNNING ===" || \
  echo "=== ERROR: demo-app failed — check: journalctl -u demo-app ==="

echo "=== Setup complete. Access at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4) ==="
echo "=== Phase 2 (EBS): see 06-commands.md for attach + mount + .env update steps ==="

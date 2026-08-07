#!/bin/bash
# =============================================================================
# op-smb-server-userdata.sh
# EC2 User Data — OP SMB Server (t4g.micro, Amazon Linux 2023, ARM64)
# Installs Samba, creates guest share "smb", pre-populates demo files + images
# =============================================================================
set -euo pipefail
exec > >(tee /var/log/op-smb-setup.log | logger -t op-smb-setup) 2>&1

SMB_SHARE_DIR="/data/smb"
SHARE_NAME="smb"
IMAGES_REPO="https://github.com/vietaws/images.git"
IMAGES_BRANCH="main"
DATASYNC_USER="datasync"
DATASYNC_PASS="Datasync@123"

echo "=== Starting op-smb-server setup ==="

# ---------------------------------------------------------------------------
# 1. System update and packages
# ---------------------------------------------------------------------------
dnf update -y
dnf install -y samba samba-client git

# ---------------------------------------------------------------------------
# 2. Create share directory and pre-populate from GitHub
# ---------------------------------------------------------------------------
mkdir -p "${SMB_SHARE_DIR}"
chmod -R 777 "$SMB_SHARE_DIR"

# ---------------------------------------------------------------------------
# 3. Clone provider image from GitHub and copy to SMB share root
# ---------------------------------------------------------------------------
git clone --depth 1 --branch "$IMAGES_BRANCH" "$IMAGES_REPO" /tmp/images-repo
cp /tmp/images-repo/provider-1.jpg "${SMB_SHARE_DIR}/"
rm -rf /tmp/images-repo
chmod 666 "${SMB_SHARE_DIR}"/*.jpg

echo "Images copied: $(ls ${SMB_SHARE_DIR}/*.jpg)"

# ---------------------------------------------------------------------------
# 4. Configure Samba — guest share, no password required
# ---------------------------------------------------------------------------
cat > /etc/samba/smb.conf << SMBCONF
[global]
  workgroup      = WORKGROUP
  security       = user
  map to guest   = Bad User
  log file       = /var/log/samba/%m.log
  max log size   = 50
  passdb backend = tdbsam

[${SHARE_NAME}]
  path           = ${SMB_SHARE_DIR}
  browsable      = yes
  writable       = yes
  guest ok       = yes
  guest only     = yes
  read only      = no
  create mask    = 0777
  directory mask = 0777
  force user     = nobody
SMBCONF

# ---------------------------------------------------------------------------
# 5. Enable and start Samba services
# ---------------------------------------------------------------------------
systemctl enable --now smb nmb

# ---------------------------------------------------------------------------
# 6. Create DataSync Samba user for DataSync agent authentication
# ---------------------------------------------------------------------------
useradd -M -s /sbin/nologin "$DATASYNC_USER"
printf '%s\n%s\n' "$DATASYNC_PASS" "$DATASYNC_PASS" | smbpasswd -a -s "$DATASYNC_USER"
echo "DataSync Samba user created: $DATASYNC_USER"

# ---------------------------------------------------------------------------
# 7. Verify
# ---------------------------------------------------------------------------
testparm -s 2>/dev/null | grep -A8 "\[${SHARE_NAME}\]" || true
pdbedit -L
echo "=== op-smb-server setup complete ==="
echo "Share        : //<this-private-ip>/${SHARE_NAME}"
echo "Path         : ${SMB_SHARE_DIR}"
echo "Files        : $(ls ${SMB_SHARE_DIR})"
echo "Mount(guest) : mount -t cifs -o guest,vers=3.0 //<this-private-ip>/${SHARE_NAME} /mnt/smb"
echo "Mount(auth)  : mount -t cifs -o username=${DATASYNC_USER},vers=3.0 //<this-private-ip>/${SHARE_NAME} /mnt/smb"

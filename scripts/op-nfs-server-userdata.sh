#!/bin/bash
# =============================================================================
# op-nfs-server-userdata.sh
# EC2 User Data — OP NFS Server (t4g.micro, Amazon Linux 2023, ARM64)
# Installs NFS server, exports /data/nfs, pre-populates demo files + images
# =============================================================================
set -euo pipefail
exec > >(tee /var/log/op-nfs-setup.log | logger -t op-nfs-setup) 2>&1

NFS_EXPORT_DIR="/data/nfs"
ALLOWED_CIDR="10.1.0.0/16"
IMAGES_REPO="https://github.com/vietaws/images.git"
IMAGES_BRANCH="main"

echo "=== Starting op-nfs-server setup ==="

# ---------------------------------------------------------------------------
# 1. System update and packages
# ---------------------------------------------------------------------------
dnf update -y
dnf install -y nfs-utils git

# ---------------------------------------------------------------------------
# 2. Create export directory and pre-populate from GitHub
# ---------------------------------------------------------------------------
mkdir -p "${NFS_EXPORT_DIR}"
chmod -R 777 "$NFS_EXPORT_DIR"

# ---------------------------------------------------------------------------
# 3. Clone product images from GitHub and copy to NFS export root
# ---------------------------------------------------------------------------
git clone --depth 1 --branch "$IMAGES_BRANCH" "$IMAGES_REPO" /tmp/images-repo
cp /tmp/images-repo/product-1.jpg "${NFS_EXPORT_DIR}/"
cp /tmp/images-repo/product-2.jpg "${NFS_EXPORT_DIR}/"
cp /tmp/images-repo/product-3.jpg "${NFS_EXPORT_DIR}/"
rm -rf /tmp/images-repo
chmod 644 "${NFS_EXPORT_DIR}"/*.jpg

echo "Images copied: $(ls ${NFS_EXPORT_DIR}/*.jpg)"

# ---------------------------------------------------------------------------
# 4. Configure NFS exports
# ---------------------------------------------------------------------------
echo "${NFS_EXPORT_DIR} ${ALLOWED_CIDR}(rw,sync,no_root_squash,no_subtree_check)" > /etc/exports

# ---------------------------------------------------------------------------
# 5. Enable and start NFS server
#    Note: "active (exited)" is the correct status for nfs-server on AL2023.
#    The service unit exits after launching the NFS daemons in the background.
# ---------------------------------------------------------------------------
systemctl enable nfs-server
systemctl start  nfs-server
exportfs -rav

# ---------------------------------------------------------------------------
# 6. Verify — confirm NFS is listening on port 2049
# ---------------------------------------------------------------------------
exportfs -v
rpcinfo -p localhost | grep nfs || true

# Wait up to 10s for port 2049 to be ready
for i in $(seq 1 5); do
  if ss -tnlp | grep -q ':2049'; then
    echo "NFS port 2049 is listening"
    break
  fi
  echo "Waiting for NFS port 2049... attempt $i"
  sleep 2
done

echo "=== op-nfs-server setup complete ==="
echo "Export  : ${NFS_EXPORT_DIR}"
echo "Allowed : ${ALLOWED_CIDR}"
echo "Files   : $(ls ${NFS_EXPORT_DIR})"
echo "Mount   : mount -t nfs -o vers=4 <this-private-ip>:${NFS_EXPORT_DIR} /mnt/nfs"

# Cloud App Server (cloud-app) Commands

---

## 1. Verify Setup

```bash
# Check setup log
cat /var/log/cloud-app-setup.log

# Check app status
systemctl status demo-app
journalctl -u demo-app -n 50 --no-pager

# Check mounts
df -h | grep -E "efs|ebs|Filesystem"

# Check .env
cat /opt/app/.env
```

---

## 2. EFS Verification and Mount

```bash
EFS_ID="fs-09228f1437e0f3202"
EFS_MOUNT_TARGET_IP="10.1.0.61"

# Test DNS resolution
nslookup ${EFS_ID}.efs.us-east-1.amazonaws.com 169.254.169.253

# Mount via DNS
mount -t efs -o tls,iam ${EFS_ID}:/ /mnt/efs

# Mount via IP (if DNS not resolving)
mount -t nfs4 \
  -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 \
  ${EFS_MOUNT_TARGET_IP}:/ /mnt/efs

# Verify
df -h /mnt/efs
ls -lh /mnt/efs/

# Unmount
umount /mnt/efs
```

---

## 3. S3 Verification

```bash
S3_BUCKET="demo-cf-274595021951-us-east-1-an"

# List images prefix
aws s3 ls "s3://${S3_BUCKET}/images/" --region us-east-1

# List providers prefix
aws s3 ls "s3://${S3_BUCKET}/providers/" --region us-east-1
```

---

## 4. SGW Cache Refresh

Run after DataSync syncs data to S3 — SGW needs to be told to re-read the bucket.

```bash
# Get file share ARNs
aws storagegateway list-file-shares \
  --region us-east-1 \
  --query 'FileShareInfoList[*].{Type:FileShareType,ARN:FileShareARN,Status:FileShareStatus}' \
  --output table

# Refresh NFS file share cache
aws storagegateway refresh-cache \
  --region us-east-1 \
  --file-share-arn "<NFS_FILE_SHARE_ARN>"

# Refresh SMB file share cache
aws storagegateway refresh-cache \
  --region us-east-1 \
  --file-share-arn "<SMB_FILE_SHARE_ARN>"
```

Then on op-app, wait ~30 seconds and check:
```bash
ls -lh /mnt/nfs
ls -lh /mnt/smb
```

---

## 5. Switch Storage Mode (EFS ↔ EBS)

**Connect to cloud-app via SSM first:**
```bash
aws ssm start-session --target <cloud-app-instance-id> --region us-east-1
```

### Switch to EBS mode (after attaching EBS volume from snapshot)

```bash
# Check attached disk
lsblk
# nvme1n1p2 is the NTFS data partition

# Mount NTFS volume
mount -t ntfs-3g /dev/nvme1n1p2 /mnt/ebs

# Verify files
ls -lh /mnt/ebs/

# Switch app
sed -i 's/STORAGE_MODE=efs/STORAGE_MODE=ebs/' /opt/app/.env
sed -i 's|LOCAL_MOUNT=.*|LOCAL_MOUNT=/mnt/ebs|' /opt/app/.env
sed -i 's|LOCAL_SUBDIR=.*|LOCAL_SUBDIR=/|' /opt/app/.env

cat /opt/app/.env
systemctl restart demo-app
systemctl is-active demo-app
```

### Switch back to EFS mode

```bash
umount /mnt/ebs
sed -i 's/STORAGE_MODE=ebs/STORAGE_MODE=efs/' /opt/app/.env
sed -i 's|LOCAL_MOUNT=.*|LOCAL_MOUNT=/mnt/efs|' /opt/app/.env
sed -i 's|LOCAL_SUBDIR=.*|LOCAL_SUBDIR=/|' /opt/app/.env
systemctl restart demo-app
systemctl is-active demo-app
```

---

## 6. Troubleshooting

### EFS DNS not resolving (NXDOMAIN)
```bash
# Test against VPC DNS resolver directly
nslookup <EFS_ID>.efs.us-east-1.amazonaws.com 169.254.169.253

# Check VPC DNS settings
aws ec2 describe-vpc-attribute --vpc-id <VPC_ID> --attribute enableDnsSupport
aws ec2 describe-vpc-attribute --vpc-id <VPC_ID> --attribute enableDnsHostnames

# Workaround — mount by IP
mount -t nfs4 -o nfsvers=4.1,hard 10.1.0.61:/ /mnt/efs
```

### ntfs-3g dirty NTFS on mount
```
The disk contains an unclean file system — Falling back to read-only mount
```
Read-only is fine for cloud-app (display only). See `09-iscsi-commands.md` Section 5 for full explanation and clean snapshot workflow.

### App not showing images from EBS
```bash
# Check mount
df -h /mnt/ebs
ls -lh /mnt/ebs/

# Check .env
cat /opt/app/.env

# Ensure LOCAL_SUBDIR=/ for EBS (files are at root of Z:\)
grep LOCAL_SUBDIR /opt/app/.env

# Restart app
systemctl restart demo-app
journalctl -u demo-app -n 20 --no-pager
```

### App not showing images from S3
```bash
# Check S3 prefix matches .env S3_PREFIX
grep S3_PREFIX /opt/app/.env
aws s3 ls "s3://<bucket>/<prefix>/" --region us-east-1
# Note: S3_PREFIX must NOT start with /
```

# 06 — Useful Commands: NFS & SMB Verification
**Region:** us-east-1  
**OnPrem VPC:** 10.1.0.0/16 | **Cloud VPC:** 10.0.0.0/16

Replace `<NFS_SERVER_IP>` and `<SMB_SERVER_IP>` with the actual private IPs of your EC2 instances.

---

## 1. NFS Verification

### On `op-nfs-server` (the NFS server itself)

```bash
# Check NFS server is running
# NOTE: "active (exited)" is the CORRECT status on Amazon Linux 2023.
# The service unit exits after launching NFS daemons in the background.
# "active (running)" is NOT expected for nfs-server.
systemctl status nfs-server

# Confirm NFS daemons and port 2049 are actually up
rpcinfo -p localhost | grep nfs
ss -tnlp | grep :2049

# Check NFS Logs
cat /var/log/op-nfs-setup.log

# Show active exports
exportfs -v

# Show connected NFS clients
ss -tnp | grep :2049

# List exported files
ls -lh /data/nfs/
```

---

### From `op-app` server (OnPrem VPC — same VPC as NFS server)

```bash
# Test NFS connectivity — list available exports from server
showmount -e <NFS_SERVER_IP>

# Mount the NFS share manually
sudo mount -t nfs -o vers=4 <NFS_SERVER_IP>:/data/nfs /mnt/nfs

# Verify mount
mount | grep nfs
df -h /mnt/nfs

# List files
ls -lh /mnt/nfs/

# Test write access
echo "test from op-app - $(date)" > /mnt/nfs/op-app-test.txt
cat /mnt/nfs/op-app-test.txt

# Unmount
sudo umount /mnt/nfs
```

---

### From `op-sgw-appliance` (OnPrem VPC — Storage Gateway)

```bash
# Connect via SSM then test NFS reachability
showmount -e <NFS_SERVER_IP>

# Verify NFS port is reachable
nc -zv <NFS_SERVER_IP> 2049
nc -zv <NFS_SERVER_IP> 111
```

---

### From `op-datasync-agent` (OnPrem VPC — DataSync Agent)

```bash
# Connect via SSM then verify NFS server reachability
showmount -e <NFS_SERVER_IP>

# Port check (DataSync agent needs TCP 2049 + TCP 111)
nc -zv <NFS_SERVER_IP> 2049
nc -zv <NFS_SERVER_IP> 111
```

---

### From `cloud-app` server (Cloud VPC — via VPC Peering)

```bash
# Install NFS client if not present
sudo dnf install -y nfs-utils

# Test NFS export visibility across VPC peering
showmount -e <NFS_SERVER_IP>

# Mount across VPC peering
sudo mkdir -p /mnt/op-nfs
sudo mount -t nfs -o vers=4 <NFS_SERVER_IP>:/data/nfs /mnt/op-nfs

# Verify
ls -lh /mnt/op-nfs/

# Unmount
sudo umount /mnt/op-nfs
```

---

## 2. SMB Verification

### On `op-smb-server` (the SMB/Samba server itself)

```bash
# Check Samba services are running
systemctl status smb nmb

# Validate smb.conf configuration
testparm -s

# Show active Samba shares
smbclient -L localhost -N

# Show connected SMB clients
smbstatus

# List shared files
ls -lh /data/smb/
```

---

### From `op-app` server (OnPrem VPC — same VPC as SMB server)

```bash
# Install CIFS client if not present
sudo dnf install -y cifs-utils

# List available shares from SMB server
smbclient -L //<SMB_SERVER_IP> -N

# Mount the SMB share (guest access)
sudo mount -t cifs -o guest,vers=3.0 //<SMB_SERVER_IP>/smb /mnt/smb

# Verify mount
mount | grep cifs
df -h /mnt/smb

# List files
ls -lh /mnt/smb/

# Test write access
echo "test from op-app - $(date)" > /mnt/smb/op-app-test.txt
cat /mnt/smb/op-app-test.txt

# Unmount
sudo umount /mnt/smb
```

---

### From `op-datasync-agent` (OnPrem VPC — DataSync Agent)

```bash
# Verify SMB port reachability
nc -zv <SMB_SERVER_IP> 445
nc -zv <SMB_SERVER_IP> 139

# List shares (DataSync uses SMB credentials — guest for this demo)
smbclient -L //<SMB_SERVER_IP> -N
```

---

### From `cloud-app` server (Cloud VPC — via VPC Peering)

```bash
# Install CIFS client if not present
sudo dnf install -y cifs-utils

# List available shares
smbclient -L //<SMB_SERVER_IP> -N

# Mount across VPC peering
sudo mkdir -p /mnt/op-smb
sudo mount -t cifs -o guest,vers=3.0 //<SMB_SERVER_IP>/smb /mnt/op-smb

# Verify
ls -lh /mnt/op-smb/

# Unmount
sudo umount /mnt/op-smb
```

---

## 3. Network Connectivity Quick Checks

### Verify VPC Peering routes work (from Cloud VPC to OnPrem VPC)

```bash
# From cloud-app EC2 — ping OnPrem instances
ping -c 3 <NFS_SERVER_IP>
ping -c 3 <SMB_SERVER_IP>

# From op-app EC2 — ping Cloud EFS mount target
ping -c 3 <EFS_MOUNT_TARGET_IP>
```

### Port reachability matrix

```bash
# NFS ports
nc -zv <NFS_SERVER_IP> 111    # portmapper
nc -zv <NFS_SERVER_IP> 2049   # NFS

# SMB ports
nc -zv <SMB_SERVER_IP> 445    # SMB
nc -zv <SMB_SERVER_IP> 139    # NetBIOS

# Storage Gateway ports (from iSCSI client)
nc -zv <SGW_APPLIANCE_IP> 3260  # iSCSI
nc -zv <SGW_APPLIANCE_IP> 80    # activation
nc -zv <SGW_APPLIANCE_IP> 2049  # NFS (File Gateway clients)
nc -zv <SGW_APPLIANCE_IP> 445   # SMB (File Gateway clients)
```

---

## 4. Check Setup Logs (after EC2 launch via userdata)

```bash
# NFS server setup log
sudo cat /var/log/op-nfs-setup.log

# SMB server setup log
sudo cat /var/log/op-smb-setup.log

# cloud-app setup log
sudo cat /var/log/cloud-app-setup.log

# op-app setup log
sudo cat /var/log/op-app-setup.log

# App service status
sudo systemctl status demo-app
sudo journalctl -u demo-app -n 50 --no-pager
```

---

## 5. EFS Verification (from Cloud VPC)

```bash
# From cloud-app EC2
# EFS_DNS format: <fs-id>.efs.us-east-1.amazonaws.com

# Mount EFS
sudo mount -t efs -o tls,iam <EFS_ID>:/ /mnt/efs

# Verify
df -h /mnt/efs
ls -lh /mnt/efs/images/products/

# Unmount
sudo umount /mnt/efs
```

---

## 6. Instance IP Reference (fill in after launch)

| Instance | Private IP | Public IP |
|----------|-----------|-----------|
| op-nfs-server | | |
| op-smb-server | | |
| op-iscsi-client | | |
| op-sgw-appliance | | |
| op-datasync-agent | | |
| op-app | | |
| cloud-app | | |

---

## 7. Phase Transition: DataSync (S3 + EFS) → Storage Gateway (S3 + EBS)

Run these steps after completing the DataSync demo and before starting the Storage Gateway Volume Gateway demo.

**Pre-requisite:** Volume Gateway iSCSI demo (SGW-05/SGW-06) must have run and created at least one EBS snapshot.

### Step 1 — Find the Volume Gateway snapshot

```bash
# List snapshots from Volume Gateway (filter by description)
aws ec2 describe-snapshots \
  --region us-east-1 \
  --filters "Name=status,Values=completed" \
  --query 'sort_by(Snapshots, &StartTime)[-1].{SnapshotId:SnapshotId,StartTime:StartTime,Description:Description}' \
  --output table
```

### Step 2 — Create EBS volume from snapshot

```bash
# Must be in same AZ as cloud-app EC2 (us-east-1a)
aws ec2 create-volume \
  --region us-east-1 \
  --availability-zone us-east-1a \
  --snapshot-id <SNAPSHOT_ID> \
  --volume-type gp3 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=sgw-demo-ebs-restore}]'

# Note the VolumeId from output
```

### Step 3 — Attach EBS volume to cloud-app EC2

```bash
aws ec2 attach-volume \
  --region us-east-1 \
  --volume-id <VOLUME_ID> \
  --instance-id <CLOUD_APP_INSTANCE_ID> \
  --device /dev/xvdf

# Wait for attachment to complete
aws ec2 wait volume-in-use --region us-east-1 --volume-ids <VOLUME_ID>
echo "Volume attached"
```

### Step 4 — Mount NTFS volume on cloud-app EC2 (via SSM)

```bash
# ntfs-3g is already installed by userdata — no install needed
sudo mount -t ntfs-3g /dev/xvdf /mnt/ebs

# Verify files are visible (files written from Windows Z:\ session)
ls -lh /mnt/ebs/
```

### Step 5 — Switch app to EBS mode

```bash
# Update .env
sudo sed -i 's/STORAGE_MODE=efs/STORAGE_MODE=ebs/' /opt/app/.env
sudo sed -i 's|LOCAL_MOUNT=.*|LOCAL_MOUNT=/mnt/ebs|' /opt/app/.env

# Verify
cat /opt/app/.env

# Restart app
sudo systemctl restart demo-app
sudo systemctl is-active demo-app
```

### Step 6 — Verify in browser

- Refresh `http://<cloud-app-public-ip>`
- Tab 2 label changes: **"Amazon EFS"** → **"Amazon EBS"**
- Files written from Windows `Z:\` during Volume Gateway demo appear in the grid

### Switch back to EFS (if needed)

```bash
sudo umount /mnt/ebs
sudo sed -i 's/STORAGE_MODE=ebs/STORAGE_MODE=efs/' /opt/app/.env
sudo sed -i 's|LOCAL_MOUNT=.*|LOCAL_MOUNT=/mnt/efs|' /opt/app/.env
sudo systemctl restart demo-app
```

---

## 8. Windows iSCSI Client Verification (op-iscsi-client)

Connect via SSM Session Manager → select the Windows instance → Start session (PowerShell).

### 8.1 Verify userdata ran successfully

```powershell
# Check setup log
Get-Content C:\demo-setup.log

# Expected output includes:
#   iSCSI Initiator service started
#   iSCSI firewall rules enabled
#   C:\demo-iscsi folder created
#   Downloaded: provider-1.jpg
#   Downloaded: provider-2.jpg
#   Downloaded: provider-3.jpg
#   Power plan set to High Performance
#   op-iscsi-client setup complete
```

### 8.2 Verify downloaded images

```powershell
# List demo images
Get-ChildItem C:\demo-iscsi\

# Check file sizes (should be non-zero)
Get-ChildItem C:\demo-iscsi\ | Select-Object Name, Length

# Quick check all 3 exist
$expected = @("provider-1.jpg", "provider-2.jpg", "provider-3.jpg")
foreach ($f in $expected) {
  $path = "C:\demo-iscsi\$f"
  if (Test-Path $path) {
    Write-Host "OK: $f ($((Get-Item $path).Length) bytes)"
  } else {
    Write-Host "MISSING: $f"
  }
}
```

### 8.3 Verify iSCSI Initiator service

```powershell
# Check service is running
Get-Service MSiSCSI | Select-Object Name, Status, StartType

# Expected: Status=Running, StartType=Automatic
```

### 8.4 Re-download images if missing (run manually)

```powershell
$images  = @("provider-1.jpg", "provider-2.jpg", "provider-3.jpg")
$baseUrl = "https://raw.githubusercontent.com/vietaws/images/main"
New-Item -ItemType Directory -Force -Path "C:\demo-iscsi" | Out-Null
foreach ($img in $images) {
  Invoke-WebRequest -Uri "$baseUrl/$img" -OutFile "C:\demo-iscsi\$img" -UseBasicParsing
  Write-Host "Downloaded: $img"
}
```

### 8.5 Connect to Storage Gateway iSCSI volume (after SGW appliance is activated)

```powershell
# Add iSCSI target portal (replace with SGW appliance private IP)
New-IscsiTargetPortal -TargetPortalAddress "<SGW_APPLIANCE_PRIVATE_IP>"

# Discover available targets
Get-IscsiTarget

# Connect to the target (replace TargetNodeAddress from above output)
Connect-IscsiTarget -NodeAddress "<TARGET_NODE_ADDRESS>" -IsPersistent $true

# Verify connection
Get-IscsiSession
```

### 8.6 Initialize and format the iSCSI disk (after connecting)

```powershell
# Find the new raw disk (Status = Offline or RAW)
Get-Disk | Where-Object {$_.PartitionStyle -eq "RAW" -or $_.OperationalStatus -eq "Offline"}

# Initialize, partition, format and assign drive letter Z:
$disk = Get-Disk | Where-Object PartitionStyle -eq "RAW" | Select-Object -First 1
Initialize-Disk -Number $disk.Number -PartitionStyle GPT
$partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter Z
Format-Volume -DriveLetter Z -FileSystem NTFS -NewFileSystemLabel "iSCSI-Demo" -Confirm:$false
Write-Host "Drive Z: ready"
```

### 8.7 Copy demo images to iSCSI volume

```powershell
# Copy downloaded images to Z:\ (triggers Volume Gateway to sync to AWS)
Copy-Item C:\demo-iscsi\*.jpg Z:\

# Verify on Z:\
Get-ChildItem Z:\ | Select-Object Name, Length, LastWriteTime
```

### 8.8 Verify Volume Gateway snapshot in AWS (after copying files)

```bash
# Run from your local machine or AWS CloudShell
aws ec2 describe-snapshots \
  --region us-east-1 \
  --filters "Name=status,Values=pending,completed" \
  --query 'sort_by(Snapshots, &StartTime)[-3:].{SnapshotId:SnapshotId,State:State,StartTime:StartTime,Description:Description}' \
  --output table
```

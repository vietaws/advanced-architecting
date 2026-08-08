# 07 — iSCSI + Volume Gateway Demo Commands
**Region:** us-east-1
**OnPrem VPC:** 10.1.0.0/16 | **Volume Gateway IP:** 10.1.0.126

---

## 1. Prerequisites

### Verify op-iscsi-client setup (PowerShell on Windows)

```powershell
# Check setup log
Get-Content C:\demo-setup.log

# Verify iSCSI service running
Get-Service MSiSCSI | Select-Object Name, Status, StartType

# Verify demo images exist
Get-ChildItem C:\demo-iscsi\ | Select-Object Name, Length

# Verify network connectivity to Volume Gateway (port 3260)
Test-NetConnection -ComputerName <SGW_APPLIANCE_PRIVATE_IP> -Port 3260
```

Expected results:
- Service: `Status=Running, StartType=Automatic`
- 3 jpg files: `flower-1.jpg`, `flower-2.jpg`, `flower-3.jpg` with non-zero size
- `TcpTestSucceeded: True`

### If setup log missing — run setup manually

```powershell
New-Item -ItemType Directory -Force -Path "C:\demo-iscsi" | Out-Null

$images = @("flower-1.jpg", "flower-2.jpg", "flower-3.jpg")
$baseUrl = "https://raw.githubusercontent.com/vietaws/images/main"
foreach ($img in $images) {
  Invoke-WebRequest -Uri "$baseUrl/$img" -OutFile "C:\demo-iscsi\$img" -UseBasicParsing
  Write-Host "Downloaded: $img"
}

Set-Service -Name MSiSCSI -StartupType Automatic
Start-Service MSiSCSI

Get-ChildItem C:\demo-iscsi\
Get-Service MSiSCSI | Select-Object Name, Status, StartType
```

---

## 2. Windows Client — Connect iSCSI to Volume Gateway

Run on `op-iscsi-client` via PowerShell.

### Step 1 — Discover iSCSI target portal

```powershell
New-IscsiTargetPortal -TargetPortalAddress "<SGW_APPLIANCE_PRIVATE_IP>"

# Verify portal registered
Get-IscsiTargetPortal
```

### Step 2 — List discovered targets

```powershell
Get-IscsiTarget
# Note the NodeAddress — e.g. iqn.1997-05.com.amazon:cloud-iscsi
```

### Step 3 — Connect to iSCSI target

```powershell
$target = (Get-IscsiTarget).NodeAddress
Connect-IscsiTarget -NodeAddress $target -IsPersistent $true

# Verify connected
Get-IscsiTarget
Get-IscsiSession
```

### Step 4 — Bring disk online

```powershell
# Check new disk appeared (should be RAW, Offline)
Get-Disk | Select-Object Number, Size, PartitionStyle, OperationalStatus

# Bring online
Set-Disk -Number 1 -IsOffline $false
Set-Disk -Number 1 -IsReadOnly $false
```

### Step 5 — Initialize, format NTFS, assign Z:

```powershell
$disk = Get-Disk | Where-Object PartitionStyle -eq "RAW" | Select-Object -First 1
Initialize-Disk -Number $disk.Number -PartitionStyle GPT
New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter Z
Format-Volume -DriveLetter Z -FileSystem NTFS -NewFileSystemLabel "iSCSI-Demo" -Confirm:$false
Write-Host "Drive Z: ready"

# Verify
Get-PSDrive Z
```

### Step 6 — Copy demo images to Z:\

```powershell
Copy-Item C:\demo-iscsi\*.jpg Z:\

# Verify files on Z:\
Get-ChildItem Z:\ | Select-Object Name, Length, LastWriteTime
```

### Step 7 — Clean disconnect before snapshot (IMPORTANT)

```powershell
# Disconnect cleanly to flush NTFS journal — prevents dirty NTFS on Linux mount
Disconnect-IscsiTarget -NodeAddress "iqn.1997-05.com.amazon:cloud-iscsi" -Confirm:$false

# Verify disconnected
Get-IscsiTarget
```

### Step 8 — Reconnect after snapshot starts

```powershell
Connect-IscsiTarget -NodeAddress "iqn.1997-05.com.amazon:cloud-iscsi" -IsPersistent $true
Get-IscsiTarget
```

---

## 3. AWS Side — Snapshot and EBS Restore

Run from local machine or CloudShell.

```bash
GATEWAY_ARN="arn:aws:storagegateway:us-east-1:274595021951:gateway/sgw-62E3260A"
VOLUME_ARN="arn:aws:storagegateway:us-east-1:274595021951:gateway/sgw-62E3260A/volume/vol-04991AC2888CBD899"
```

### Check volume status

```bash
aws storagegateway list-volumes \
  --region us-east-1 \
  --gateway-arn "$GATEWAY_ARN" \
  --query 'VolumeInfos[*].{VolumeId:VolumeId,ARN:VolumeARN,Status:VolumeStatus,Type:VolumeType}' \
  --output table

aws storagegateway describe-stored-iscsi-volumes \
  --region us-east-1 \
  --volume-arns "$VOLUME_ARN" \
  --query 'StorediSCSIVolumes[*].{Status:VolumeStatus,AttachStatus:VolumeAttachmentStatus,UsedBytes:VolumeUsedInBytes,ChapEnabled:VolumeiSCSIAttributes.ChapEnabled}' \
  --output table
```

### Check snapshot schedule

```bash
aws storagegateway describe-snapshot-schedule \
  --region us-east-1 \
  --volume-arn "$VOLUME_ARN" \
  --output json
```

### Update snapshot schedule (e.g. every 1 hour)

```bash
aws storagegateway update-snapshot-schedule \
  --region us-east-1 \
  --volume-arn "$VOLUME_ARN" \
  --start-at 0 \
  --recurrence-in-hours 1 \
  --description "hourly-demo-snapshot"
```

### Trigger manual snapshot

```bash
aws storagegateway create-snapshot \
  --region us-east-1 \
  --volume-arn "$VOLUME_ARN" \
  --snapshot-description "demo-manual-snapshot"
```

### Wait for snapshot to complete

```bash
aws ec2 describe-snapshots \
  --region us-east-1 \
  --filters "Name=status,Values=pending,completed" \
  --query 'sort_by(Snapshots, &StartTime)[-3:].{SnapshotId:SnapshotId,State:State,StartTime:StartTime,Description:Description}' \
  --output table
```

### Create EBS volume from snapshot

```bash
# Must be in same AZ as cloud-app (us-east-1a)
aws ec2 create-volume \
  --region us-east-1 \
  --availability-zone us-east-1a \
  --snapshot-id <SNAPSHOT_ID> \
  --volume-type gp3 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=sgw-iscsi-restore}]'
```

### Attach EBS volume to cloud-app

```bash
aws ec2 attach-volume \
  --region us-east-1 \
  --volume-id <VOLUME_ID> \
  --instance-id <CLOUD_APP_INSTANCE_ID> \
  --device /dev/xvdf

aws ec2 wait volume-in-use --region us-east-1 --volume-ids <VOLUME_ID>
echo "Volume attached"
```

---

## 4. cloud-app — Mount EBS and Switch App

Run on `cloud-app` via SSM.

### Step 1 — Check attached disk

```bash
lsblk
# Look for new disk e.g. nvme1n1 with two partitions:
# nvme1n1p1 — 16MB GPT metadata
# nvme1n1p2 — 20GB NTFS data partition
```

### Step 2 — Mount NTFS data partition

```bash
# Mount using ntfs-3g (pre-installed by userdata)
mount -t ntfs-3g /dev/nvme1n1p2 /mnt/ebs

# Verify files from Z:\ are visible
ls -lh /mnt/ebs/
```

### Step 3 — Switch app to EBS mode

```bash
sed -i 's/STORAGE_MODE=efs/STORAGE_MODE=ebs/' /opt/app/.env
sed -i 's|LOCAL_MOUNT=.*|LOCAL_MOUNT=/mnt/ebs|' /opt/app/.env
sed -i 's|LOCAL_SUBDIR=.*|LOCAL_SUBDIR=/|' /opt/app/.env

# Verify
cat /opt/app/.env

# Restart app
systemctl restart demo-app
systemctl is-active demo-app
```

### Step 4 — Verify in browser

Open `http://<cloud-app-public-ip>` — tab 2 shows **"Amazon EBS"** and images from `Z:\` appear.

### Step 5 — Switch back to EFS mode

```bash
umount /mnt/ebs
sed -i 's/STORAGE_MODE=ebs/STORAGE_MODE=efs/' /opt/app/.env
sed -i 's|LOCAL_MOUNT=.*|LOCAL_MOUNT=/mnt/efs|' /opt/app/.env
sed -i 's|LOCAL_SUBDIR=.*|LOCAL_SUBDIR=/|' /opt/app/.env
systemctl restart demo-app
```

---

## 5. Dirty vs Clean NTFS

### WHAT is dirty NTFS?

NTFS maintains a journal (transaction log) to ensure filesystem consistency. When Windows mounts an NTFS volume, it marks the journal as "dirty" (in use). When Windows unmounts cleanly, it marks the journal as "clean" (consistent).

A **dirty NTFS** volume is one where the journal was not cleanly closed — Linux sees this and refuses to mount read-write to protect data integrity.

```
# Dirty NTFS error on Linux:
The disk contains an unclean file system (0, 0).
Metadata kept in Windows cache, refused to mount.
Falling back to read-only mount...
```

### WHY does it happen with iSCSI + snapshots?

```
Windows (iSCSI connected) → writes data → NTFS journal = DIRTY
         ↓
SGW takes snapshot of disk at this moment
         ↓
Snapshot contains dirty NTFS journal
         ↓
Linux mounts snapshot → sees dirty journal → read-only mount
```

When Windows has the iSCSI volume mounted, the NTFS journal is always dirty because Windows caches writes in memory and hasn't flushed them to disk yet.

### WHEN will you encounter it?

| Scenario | Result |
|---|---|
| Snapshot taken while Windows connected | Dirty NTFS — read-only on Linux |
| Snapshot taken after clean disconnect | Clean NTFS — read-write on Linux |
| Scheduled snapshot (Windows always connected) | Always dirty unless VSS is used |
| Manual snapshot after disconnect | Clean |

### Real world solutions

| Solution | How | Best for |
|---|---|---|
| **Clean disconnect** | Disconnect iSCSI before snapshot, reconnect after | Demo, simple workloads |
| **VSS (Volume Shadow Copy)** | Windows flushes all caches before snapshot — application-consistent | Production Windows workloads |
| **Application quiesce** | App pauses writes, snapshot taken, app resumes | Databases (SQL Server, Oracle) |
| **Maintenance window** | Schedule snapshots during low-activity period | Simple workloads |
| **AWS Backup + VSS** | AWS Backup integrates with VSS for consistent snapshots | Enterprise Windows on AWS |

### Clean disconnect workflow for demo

```powershell
# Step 1 — Disconnect iSCSI cleanly on Windows (flushes NTFS journal)
Disconnect-IscsiTarget -NodeAddress "iqn.1997-05.com.amazon:cloud-iscsi" -Confirm:$false
```

```bash
# Step 2 — Trigger snapshot immediately after disconnect
aws storagegateway create-snapshot \
  --region us-east-1 \
  --volume-arn "$VOLUME_ARN" \
  --snapshot-description "clean-snapshot"
```

```powershell
# Step 3 — Reconnect iSCSI after snapshot starts
Connect-IscsiTarget -NodeAddress "iqn.1997-05.com.amazon:cloud-iscsi" -IsPersistent $true
```

```bash
# Step 4 — Mount on Linux — no dirty warning
mount -t ntfs-3g /dev/nvme1n1p2 /mnt/ebs
ls -lh /mnt/ebs/
```

---

## 6. Troubleshooting

### Dirty NTFS on mount
```
The disk contains an unclean file system — Falling back to read-only mount
```
**Cause:** Snapshot taken while Windows had iSCSI volume mounted.
**Fix for demo:** Mount read-only is fine for cloud-app (read-only access). For clean mount next time, disconnect iSCSI before snapshot.
**Force read-write (risky — may corrupt data):**
```bash
ntfs-3g -o remove_hiberfile /dev/nvme1n1p2 /mnt/ebs
```

### Volume Status None after creation
**Cause:** Working storage or upload buffer disk not assigned correctly.
**Fix:**
```bash
aws storagegateway list-local-disks \
  --region us-east-1 \
  --gateway-arn "$GATEWAY_ARN" \
  --output table
# Assign disks correctly — see deploy-sgw-appliance.sh Step 6
```

### No RAW disk on Windows after connecting iSCSI
**Cause:** Disk is offline (Windows Server 2022 brings SAN disks offline by default).
**Fix:**
```powershell
Get-Disk | Where-Object OperationalStatus -eq "Offline"
Set-Disk -Number <N> -IsOffline $false
Set-Disk -Number <N> -IsReadOnly $false
```

### iSCSI connection refused
**Cause:** Port 3260 blocked by security group or Volume Gateway not running.
**Fix:**
```powershell
Test-NetConnection -ComputerName <SGW_IP> -Port 3260
```
Check `OnPremSGWVolumeSG` security group allows port 3260 from OnPrem VPC CIDR.

### VolumeUsedInBytes: 0 after copying files
**Cause:** SGW hasn't flushed data from upload buffer to S3 yet — normal, takes a few minutes.
**Fix:** Wait 2-3 minutes then re-check. Trigger manual snapshot to force flush.

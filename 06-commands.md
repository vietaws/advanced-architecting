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

# 07 — OnPrem App Server (op-app) Commands
**Region:** us-east-1
**OnPrem VPC:** 10.1.0.0/16

Replace `<NFS_SERVER_IP>`, `<SMB_SERVER_IP>`, `<SGW_APPLIANCE_IP>` with actual private IPs.

---

## 1. Verify Setup

```bash
# Check setup log
cat /var/log/op-app-setup.log

# Check app status
systemctl status demo-app
journalctl -u demo-app -n 50 --no-pager

# Check mounts
df -h | grep -E "nfs|cifs|Filesystem"
mount | grep -E "nfs|cifs"

# Check .env
cat /opt/app/.env
```

---

## 2. NFS Verification

### On op-nfs-server

```bash
# Check NFS server status
# NOTE: "active (exited)" is CORRECT on AL2023 — NFS daemons run in background
systemctl status nfs-server
rpcinfo -p localhost | grep nfs
ss -tnlp | grep :2049

# Show active exports
exportfs -v

# List NFS files
ls -lh /data/nfs/

# Check setup log
cat /var/log/op-nfs-setup.log
```

### From op-app

```bash
# List available exports from NFS server
showmount -e <NFS_SERVER_IP>

# Test mount manually
mkdir -p /tmp/test-nfs
mount -t nfs -o vers=4 <NFS_SERVER_IP>:/data/nfs /tmp/test-nfs
ls -lh /tmp/test-nfs/
umount /tmp/test-nfs

# Check current NFS mount
ls -lh /mnt/nfs/
df -h /mnt/nfs
```

---

## 3. SMB Verification

### On op-smb-server

```bash
# Check Samba services
systemctl status smb nmb

# Validate config
testparm -s

# List Samba users
pdbedit -L

# List shared files
ls -lh /data/smb/

# Check setup log
cat /var/log/op-smb-setup.log
```

### From op-app

```bash
# List available shares
smbclient -L //<SMB_SERVER_IP> -N

# Test mount manually (local guest, no password)
mkdir -p /tmp/test-smb
mount -t cifs -o guest,vers=3.0 //<SMB_SERVER_IP>/smb /tmp/test-smb
ls -lh /tmp/test-smb/
umount /tmp/test-smb

# Check current SMB mount
ls -lh /mnt/smb/
df -h /mnt/smb
```

---

## 4. Switch NFS Mount (op-nfs-server ↔ SGW File Gateway)

**Connect to op-app via SSM first:**
```bash
aws ssm start-session --target <op-app-instance-id> --region us-east-1
```

### Phase 1 → Phase 2: Switch to SGW File Gateway NFS

```bash
SGW_IP="<sgw-appliance-private-ip>"
SGW_NFS_PATH="/<nfs-share-path>"    # NFS export path shown in SGW console

umount /mnt/nfs

mount -t nfs \
  -o vers=4,hard,intr \
  "${SGW_IP}:${SGW_NFS_PATH}" /mnt/nfs

df -h /mnt/nfs && ls -lh /mnt/nfs
systemctl restart demo-app
systemctl is-active demo-app
```

### Phase 2 → Phase 1: Switch back to op-nfs-server

```bash
NFS_IP="<op-nfs-server-private-ip>"

umount /mnt/nfs
mount -t nfs -o vers=4,hard,intr "${NFS_IP}:/data/nfs" /mnt/nfs
df -h /mnt/nfs && ls -lh /mnt/nfs
systemctl restart demo-app
systemctl is-active demo-app
```

---

## 5. Switch SMB Mount (op-smb-server ↔ SGW File Gateway)

**Connect to op-app via SSM first:**
```bash
aws ssm start-session --target <op-app-instance-id> --region us-east-1
```

### Phase 1 → Phase 2: Switch to SGW File Gateway SMB

```bash
SGW_IP="<sgw-appliance-private-ip>"
SGW_SHARE="cloudsmb"
WEBAPP_UID=$(id -u webapp)
WEBAPP_GID=$(id -g webapp)

# Write credentials file (SGW guest account is "smbguest")
cat > /etc/smb-credentials << EOF
username=smbguest
password=Passw0rd123
EOF
chmod 600 /etc/smb-credentials

umount /mnt/smb

mount -t cifs \
  -o "credentials=/etc/smb-credentials,sec=ntlmsspi,uid=${WEBAPP_UID},gid=${WEBAPP_GID},file_mode=0777,dir_mode=0777" \
  "//${SGW_IP}/${SGW_SHARE}" /mnt/smb

df -h /mnt/smb && ls /mnt/smb
systemctl restart demo-app
systemctl is-active demo-app
```

### Phase 2 → Phase 1: Switch back to op-smb-server

```bash
SMB_IP="<op-smb-server-private-ip>"
WEBAPP_UID=$(id -u webapp)
WEBAPP_GID=$(id -g webapp)

umount /mnt/smb

mount -t cifs \
  -o "guest,uid=${WEBAPP_UID},gid=${WEBAPP_GID},file_mode=0777,dir_mode=0777,vers=3.0,iocharset=utf8" \
  "//${SMB_IP}/smb" /mnt/smb

df -h /mnt/smb && ls /mnt/smb
systemctl restart demo-app
systemctl is-active demo-app
```

---

## 6. Troubleshooting

### NFS mount failed
```bash
# Check NFS server is exporting
showmount -e <NFS_SERVER_IP>

# Check port reachability
bash -c 'echo >/dev/tcp/<NFS_SERVER_IP>/2049' && echo "OPEN" || echo "CLOSED"
bash -c 'echo >/dev/tcp/<NFS_SERVER_IP>/111'  && echo "OPEN" || echo "CLOSED"

# Check NFS server logs
cat /var/log/op-nfs-setup.log
```

### SMB mount failed — Permission denied
```bash
# Test SMB connectivity
smbclient -L //<SMB_SERVER_IP> -N

# For SGW SMB — verify smbguest credentials
smbclient "//<SGW_IP>/cloudsmb" -U 'smbguest%Passw0rd123' -m SMB2

# Check credentials file
cat /etc/smb-credentials
```

### App not showing files
```bash
# Check mount is active
df -h | grep -E "nfs|cifs"

# Check app .env
cat /opt/app/.env

# Check app logs
journalctl -u demo-app -n 30 --no-pager
```

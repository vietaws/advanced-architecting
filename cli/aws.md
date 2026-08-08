# 06 — AWS Side Commands


---

## DataSync

### List agents
```bash
aws datasync list-agents \
  --region us-east-1 \
  --query 'Agents[*].{Name:Name,ARN:AgentArn,Status:Status}' \
  --output table
```

### List locations
```bash
aws datasync list-locations \
  --region us-east-1 \
  --query 'Locations[*].{ARN:LocationArn,URI:LocationUri}' \
  --output table
```

### List tasks
```bash
aws datasync list-tasks \
  --region us-east-1 \
  --query 'Tasks[*].{Name:Name,ARN:TaskArn,Status:Status}' \
  --output table
```

### Start task execution
```bash
aws datasync start-task-execution \
  --region us-east-1 \
  --task-arn "<TASK_ARN>"
```

### Check task execution status
```bash
aws datasync list-task-executions \
  --region us-east-1 \
  --task-arn "TASK_ARN" \
  --query 'TaskExecutions[*].{ARN:TaskExecutionArn,Status:Status}' \
  --output table
```

---

## Storage Gateway — S3 File Gateway

### List gateways
```bash
aws storagegateway list-gateways \
  --region us-east-1 \
  --query 'Gateways[*].{Name:GatewayName,State:GatewayOperationalState,Type:GatewayType,ARN:GatewayARN}' \
  --output table
```

### List file shares
```bash
aws storagegateway list-file-shares \
  --region us-east-1 \
  --query 'FileShareInfoList[*].{Type:FileShareType,Status:FileShareStatus,ARN:FileShareARN}' \
  --output table
```

### Describe SMB file share
```bash
aws storagegateway describe-smb-file-shares \
  --region us-east-1 \
  --file-share-arn-list "<SMB_FILE_SHARE_ARN>"
```

### Describe NFS file share
```bash
aws storagegateway describe-nfs-file-shares \
  --region us-east-1 \
  --file-share-arn-list "<NFS_FILE_SHARE_ARN>"
```

### Refresh cache (after DataSync syncs data to S3)
```bash
# NFS file share
aws storagegateway refresh-cache \
  --region us-east-1 \
  --file-share-arn "<NFS_FILE_SHARE_ARN>"

# SMB file share
aws storagegateway refresh-cache \
  --region us-east-1 \
  --file-share-arn "<SMB_FILE_SHARE_ARN>"
```

### Check SMB settings
```bash
aws storagegateway describe-smb-settings \
  --region us-east-1 \
  --gateway-arn "GATEWAY_ARN"
```

### Set SMB guest password
```bash
aws storagegateway set-smb-guest-password \
  --region us-east-1 \
  --gateway-arn "GATEWAY_ARN" \
  --password "Passw0rd123"
```

### Update SMB security strategy
```bash
# Options: MandatoryEncryption | MandatorySigning | ClientSpecified
aws storagegateway update-smb-security-strategy \
  --region us-east-1 \
  --gateway-arn "GATEWAY_ARN" \
  --smb-security-strategy ClientSpecified
```

---

## Storage Gateway — Volume Gateway

### List volumes
```bash
aws storagegateway list-volumes \
  --region us-east-1 \
  --gateway-arn "GATEWAY_ARN" \
  --query 'VolumeInfos[*].{VolumeId:VolumeId,ARN:VolumeARN,Status:VolumeStatus,Type:VolumeType}' \
  --output table
```

### Describe stored iSCSI volumes
```bash
aws storagegateway describe-stored-iscsi-volumes \
  --region us-east-1 \
  --volume-arns "VOLUME_ARN"
```

### List local disks
```bash
aws storagegateway list-local-disks \
  --region us-east-1 \
  --gateway-arn "GATEWAY_ARN" \
  --query 'Disks[*].{DiskId:DiskId,Path:DiskPath,Node:DiskNode,SizeGB:DiskSizeInBytes,Alloc:DiskAllocationType}' \
  --output table
```

### Assign disks — FILE_S3
```bash
# Cache disk
aws storagegateway add-cache \
  --region us-east-1 \
  --gateway-arn "GATEWAY_ARN" \
  --disk-ids "DISK_ID_SDF"
```

### Assign disks — VOLUME CACHED
```bash
aws storagegateway add-cache \
  --region us-east-1 \
  --gateway-arn "GATEWAY_ARN" \
  --disk-ids "DISK_ID_SDF"

aws storagegateway add-upload-buffer \
  --region us-east-1 \
  --gateway-arn "GATEWAY_ARN" \
  --disk-ids "DISK_ID_SDG"
```

### Assign disks — VOLUME STORED
```bash
aws storagegateway add-working-storage \
  --region us-east-1 \
  --gateway-arn "GATEWAY_ARN" \
  --disk-ids "DISK_ID_SDF"

aws storagegateway add-upload-buffer \
  --region us-east-1 \
  --gateway-arn "GATEWAY_ARN" \
  --disk-ids "DISK_ID_SDG"
```

### Snapshot schedule
```bash
# Check schedule
aws storagegateway describe-snapshot-schedule \
  --region us-east-1 \
  --volume-arn "VOLUME_ARN"

# Update to every 1 hour
aws storagegateway update-snapshot-schedule \
  --region us-east-1 \
  --volume-arn "VOLUME_ARN" \
  --start-at 0 \
  --recurrence-in-hours 1 \
  --description "hourly-demo-snapshot"
```

### Create manual snapshot
```bash
aws storagegateway create-snapshot \
  --region us-east-1 \
  --volume-arn "VOLUME_ARN" \
  --snapshot-description "demo-manual-snapshot"
```

---
### Detach EBS volume
```bash
aws ec2 detach-volume \
  --region us-east-1 \
  --volume-id <VOLUME_ID>
```

---

## Network — Port Reachability Matrix

```bash
# From op-app — test NFS ports
bash -c 'echo >/dev/tcp/<NFS_SERVER_IP>/2049' && echo "2049 OPEN" || echo "2049 CLOSED"
bash -c 'echo >/dev/tcp/<NFS_SERVER_IP>/111'  && echo "111 OPEN"  || echo "111 CLOSED"

# From op-app — test SMB port
bash -c 'echo >/dev/tcp/<SMB_SERVER_IP>/445'  && echo "445 OPEN"  || echo "445 CLOSED"

# From op-iscsi-client — test iSCSI port (PowerShell)
Test-NetConnection -ComputerName <SGW_IP> -Port 3260

# From cloud-app — test EFS port
bash -c 'echo >/dev/tcp/<EFS_MOUNT_TARGET_IP>/2049' && echo "EFS 2049 OPEN" || echo "EFS 2049 CLOSED"
```

---
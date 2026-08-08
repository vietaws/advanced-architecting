# 06 — AWS Side Commands
**Region:** us-east-1
**OnPrem VPC:** 10.1.0.0/16 | **Cloud VPC:** 10.0.0.0/16

---

## 1. Instance IP Reference

| Instance | Role | Private IP | Public IP | Instance ID |
|---|---|---|---|---|
| op-nfs-server | NFS Server | | | |
| op-smb-server | SMB Server | | | |
| op-iscsi-client | Windows iSCSI Client | | | |
| op-sgw-appliance | SGW Appliance | | | |
| op-datasync-agent | DataSync Agent | | | |
| op-app | OnPrem App | | | |
| cloud-app | Cloud App | | | |

---

## 2. CFN Stack — Get Outputs

```bash
aws cloudformation describe-stacks \
  --stack-name sgw-datasync-demo-network \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' \
  --output table
```

---

## 3. DataSync

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
  --task-arn "<TASK_ARN>" \
  --query 'TaskExecutions[*].{ARN:TaskExecutionArn,Status:Status}' \
  --output table
```

---

## 4. Storage Gateway — S3 File Gateway

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
  --gateway-arn "<GATEWAY_ARN>"
```

### Set SMB guest password
```bash
aws storagegateway set-smb-guest-password \
  --region us-east-1 \
  --gateway-arn "<GATEWAY_ARN>" \
  --password "Passw0rd123"
```

### Update SMB security strategy
```bash
# Options: MandatoryEncryption | MandatorySigning | ClientSpecified
aws storagegateway update-smb-security-strategy \
  --region us-east-1 \
  --gateway-arn "<GATEWAY_ARN>" \
  --smb-security-strategy ClientSpecified
```

---

## 5. Storage Gateway — Volume Gateway

### List volumes
```bash
aws storagegateway list-volumes \
  --region us-east-1 \
  --gateway-arn "<GATEWAY_ARN>" \
  --query 'VolumeInfos[*].{VolumeId:VolumeId,ARN:VolumeARN,Status:VolumeStatus,Type:VolumeType}' \
  --output table
```

### Describe stored iSCSI volumes
```bash
aws storagegateway describe-stored-iscsi-volumes \
  --region us-east-1 \
  --volume-arns "<VOLUME_ARN>"
```

### List local disks
```bash
aws storagegateway list-local-disks \
  --region us-east-1 \
  --gateway-arn "<GATEWAY_ARN>" \
  --query 'Disks[*].{DiskId:DiskId,Path:DiskPath,Node:DiskNode,SizeGB:DiskSizeInBytes,Alloc:DiskAllocationType}' \
  --output table
```

### Assign disks — FILE_S3
```bash
# Cache disk
aws storagegateway add-cache \
  --region us-east-1 \
  --gateway-arn "<GATEWAY_ARN>" \
  --disk-ids "<DISK_ID_SDF>"
```

### Assign disks — VOLUME CACHED
```bash
aws storagegateway add-cache \
  --region us-east-1 \
  --gateway-arn "<GATEWAY_ARN>" \
  --disk-ids "<DISK_ID_SDF>"

aws storagegateway add-upload-buffer \
  --region us-east-1 \
  --gateway-arn "<GATEWAY_ARN>" \
  --disk-ids "<DISK_ID_SDG>"
```

### Assign disks — VOLUME STORED
```bash
aws storagegateway add-working-storage \
  --region us-east-1 \
  --gateway-arn "<GATEWAY_ARN>" \
  --disk-ids "<DISK_ID_SDF>"

aws storagegateway add-upload-buffer \
  --region us-east-1 \
  --gateway-arn "<GATEWAY_ARN>" \
  --disk-ids "<DISK_ID_SDG>"
```

### Snapshot schedule
```bash
# Check schedule
aws storagegateway describe-snapshot-schedule \
  --region us-east-1 \
  --volume-arn "<VOLUME_ARN>"

# Update to every 1 hour
aws storagegateway update-snapshot-schedule \
  --region us-east-1 \
  --volume-arn "<VOLUME_ARN>" \
  --start-at 0 \
  --recurrence-in-hours 1 \
  --description "hourly-demo-snapshot"
```

### Create manual snapshot
```bash
aws storagegateway create-snapshot \
  --region us-east-1 \
  --volume-arn "<VOLUME_ARN>" \
  --snapshot-description "demo-manual-snapshot"
```

---

## 6. EBS — Snapshot to Volume

### Check snapshot status
```bash
aws ec2 describe-snapshots \
  --region us-east-1 \
  --filters "Name=status,Values=pending,completed" \
  --query 'sort_by(Snapshots, &StartTime)[-3:].{SnapshotId:SnapshotId,State:State,StartTime:StartTime,Description:Description}' \
  --output table
```

### Create EBS volume from snapshot
```bash
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

### Detach EBS volume
```bash
aws ec2 detach-volume \
  --region us-east-1 \
  --volume-id <VOLUME_ID>
```

---

## 7. S3 — Verify Sync

```bash
S3_BUCKET="demo-cf-274595021951-us-east-1-an"

# List all objects
aws s3 ls "s3://${S3_BUCKET}/" --recursive --region us-east-1

# List by prefix
aws s3 ls "s3://${S3_BUCKET}/providers/" --region us-east-1
aws s3 ls "s3://${S3_BUCKET}/images/" --region us-east-1
```

---

## 8. Network — Port Reachability Matrix

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

## 9. Cleanup

```bash
REGION="us-east-1"
DEMO_PREFIX="sgw-datasync-demo"

# Step 1 — Terminate all demo EC2 instances
INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=tag:Demo,Values=$DEMO_PREFIX" "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text | tr '\n' ' ')
echo "Terminating: $INSTANCE_IDS"
aws ec2 terminate-instances --region "$REGION" --instance-ids $INSTANCE_IDS

# Step 2 — Delete Storage Gateways
aws storagegateway list-gateways --region "$REGION" \
  --query 'Gateways[*].GatewayARN' --output text | tr '\t' '\n' | while read arn; do
  echo "Deleting gateway: $arn"
  aws storagegateway delete-gateway --region "$REGION" --gateway-arn "$arn"
done

# Step 3 — Empty S3 bucket
S3_BUCKET="${DEMO_PREFIX}-$(aws sts get-caller-identity --query Account --output text)"
aws s3 rm "s3://${S3_BUCKET}" --recursive --region "$REGION"

# Step 4 — Delete CFN stack
aws cloudformation delete-stack \
  --region "$REGION" \
  --stack-name sgw-datasync-demo-network

aws cloudformation wait stack-delete-complete \
  --region "$REGION" \
  --stack-name sgw-datasync-demo-network && echo "Stack deleted successfully"
```

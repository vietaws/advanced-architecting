#!/usr/bin/env bash
# =============================================================================
# Deploy Storage Gateway Appliance EC2 Instance
# File: scripts/deploy-sgw-appliance.sh
# =============================================================================
# DESCRIPTION:
#   Launches a Storage Gateway appliance EC2 instance in the OnPrem VPC.
#   Supports S3 File Gateway and Volume Gateway (CACHED or STORED mode).
#   Activation is done separately via console or CLI after the instance is ready.
#
# GATEWAY_TYPE options:
#   FILE_S3  → S3 File Gateway (NFS/SMB share backed by S3)
#   VOLUME   → Volume Gateway (iSCSI volumes, mode set by VOLUME_MODE)
#
# VOLUME_MODE options (only used when GATEWAY_TYPE=VOLUME):
#   CACHED   → Primary data in S3, frequently accessed data cached locally
#   STORED   → Primary data stored locally, async backup to S3
#
# PREREQUISITES:
#   1. CFN stack "sgw-datasync-demo-network" deployed (03-network.yaml)
#   2. IAM instance profile "ec2-instance-role" exists with SSM permissions
#   3. AWS CLI configured with sufficient EC2 permissions
#   4. Fill in all variables in the INPUT VARIABLES section below
#
# HOW TO ACTIVATE AFTER LAUNCH:
#   METHOD A — Console (recommended):
#     1. Go to Storage Gateway console → Create gateway
#     2. Choose gateway type matching GATEWAY_TYPE
#     3. Hypervisor: Amazon EC2
#     4. Enter the PUBLIC IP of the instance as the activation URL
#     5. Complete setup: name, timezone, assign cache disk
#
#   METHOD B — CLI:
#     ACTIVATION_KEY=$(curl -s \
#       "http://<PUBLIC_IP>/?activationRegion=${REGION}&gatewayType=${GATEWAY_TYPE}&no_redirect")
#     aws storagegateway activate-gateway \
#       --region "$REGION" \
#       --activation-key "$ACTIVATION_KEY" \
#       --gateway-name "$INSTANCE_NAME" \
#       --gateway-timezone "GMT+7:00" \
#       --gateway-region "$REGION" \
#       --gateway-type "$GATEWAY_TYPE"
# =============================================================================

# =============================================================================
# GATEWAY SWITCHER — set GATEWAY_TYPE and VOLUME_MODE before running
# =============================================================================

GATEWAY_TYPE="VOLUME"    # FILE_S3 | VOLUME
VOLUME_MODE="STORED"      # CACHED | STORED (only applies when GATEWAY_TYPE=VOLUME)

# =============================================================================
# INPUT VARIABLES — fill these in before running
# =============================================================================

REGION="us-east-1"
DEMO_PREFIX="sgw-datasync-demo"

# OnPrem VPC networking (from CFN stack outputs)
VPC_ID="vpc-0b5aa307d88df28d8"               # e.g. vpc-0abc1234567890abc
SUBNET_ID="subnet-033e49de64a701a27"          # e.g. subnet-0abc1234567890abc

# Security Groups — one per gateway type (from CFN stack outputs)
SG_FILE_S3="sg-028c5abc1eca4bf8d"   # used when GATEWAY_TYPE=FILE_S3
SG_VOLUME="sg-028c5abc1eca4bf8d"    # used when GATEWAY_TYPE=VOLUME

# AMI ID — leave empty to auto-resolve from SSM (recommended)
# Or set explicitly to pin a specific version
AMI_ID=""

# =============================================================================
# FIXED CONFIG — no changes needed below this line
# =============================================================================

INSTANCE_TYPE="m5.xlarge"
IAM_INSTANCE_PROFILE="ec2-instance-role"

# =============================================================================
# STEP 1 — Validate GATEWAY_TYPE and derive dependent variables
# =============================================================================

case "$GATEWAY_TYPE" in
  FILE_S3)
    SSM_AMI_PATH="/aws/service/storagegateway/ami/FILE_S3/latest"
    SECURITY_GROUP_ID="$SG_FILE_S3"
    INSTANCE_NAME="op-sgw-s3-file-appliance"
    GATEWAY_LABEL="S3 File Gateway"
    ;;
  VOLUME)
    case "$VOLUME_MODE" in
      CACHED|STORED) ;;
      *)
        echo "ERROR: VOLUME_MODE must be CACHED or STORED (got: $VOLUME_MODE)"
        exit 1
        ;;
    esac
    # Volume Gateway AMI is the same regardless of CACHED or STORED mode
    # CACHED vs STORED is configured after activation in SGW console
    SSM_AMI_PATH="/aws/service/storagegateway/ami/${VOLUME_MODE}/latest"
    SECURITY_GROUP_ID="$SG_VOLUME"
    INSTANCE_NAME="op-sgw-volume-${VOLUME_MODE}"
    GATEWAY_LABEL="Volume Gateway (${VOLUME_MODE})"
    ;;
  *)
    echo "ERROR: GATEWAY_TYPE must be FILE_S3 or VOLUME (got: $GATEWAY_TYPE)"
    exit 1
    ;;
esac

echo "=== Deploying: $GATEWAY_LABEL ==="
echo "    Instance name : $INSTANCE_NAME"
echo "    Instance type : $INSTANCE_TYPE"
echo "    Subnet        : $SUBNET_ID"
echo "    Security group: $SECURITY_GROUP_ID"
echo "    AMI_PATH      : $SSM_AMI_PATH"

# =============================================================================
# STEP 2 — Resolve the latest Storage Gateway AMI via SSM
# Overrides AMI_ID only if it was left empty above
# =============================================================================

if [[ -z "$AMI_ID" ]]; then
  AMI_ID=$(aws ssm get-parameter \
    --name "$SSM_AMI_PATH" \
    --region "$REGION" \
    --query 'Parameter.Value' \
    --output text)
  echo "    AMI (SSM)     : $AMI_ID"
else
  echo "    AMI (pinned)  : $AMI_ID"
fi

# =============================================================================
# STEP 3 — Build block device mappings
#
# FILE_S3  : root (80 GB) + cache disk (20 GB)
# VOLUME CACHED  : root (80 GB) + cache disk (20 GB) + upload buffer (20 GB)
# VOLUME STORED  : root (80 GB) + local storage (20 GB) + upload buffer (20 GB)
# =============================================================================

if [[ "$GATEWAY_TYPE" == "FILE_S3" ]]; then
  BLOCK_DEVICES='[
    {
      "DeviceName": "/dev/xvda",
      "Ebs": { "VolumeSize": 80, "VolumeType": "gp3", "DeleteOnTermination": true, "Encrypted": true }
    },
    {
      "DeviceName": "/dev/xvdf",
      "Ebs": { "VolumeSize": 20, "VolumeType": "gp3", "DeleteOnTermination": true, "Encrypted": true }
    }
  ]'
else
  # VOLUME CACHED or STORED — two extra disks
  # NOTE: SGW Volume Gateway requires disks attached BEFORE activation
  # Use /dev/sdf and /dev/sdg — SGW AMI maps these correctly on EC2
  # Inside the instance they appear as /dev/xvdf, /dev/xvdg or /dev/nvme1n1, /dev/nvme2n1
  # SGW console shows them by disk ID — assign xvdf as cache, xvdg as upload buffer
  BLOCK_DEVICES='[
    {
      "DeviceName": "/dev/xvda",
      "Ebs": { "VolumeSize": 80, "VolumeType": "gp3", "DeleteOnTermination": true, "Encrypted": true }
    },
    {
      "DeviceName": "/dev/sdf",
      "Ebs": { "VolumeSize": 20, "VolumeType": "gp3", "DeleteOnTermination": true, "Encrypted": true }
    },
    {
      "DeviceName": "/dev/sdg",
      "Ebs": { "VolumeSize": 20, "VolumeType": "gp3", "DeleteOnTermination": true, "Encrypted": true }
    }
  ]'
fi

# =============================================================================
# STEP 4 — Launch the Storage Gateway EC2 instance
# =============================================================================

aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$SECURITY_GROUP_ID" \
  --iam-instance-profile Name="$IAM_INSTANCE_PROFILE" \
  --associate-public-ip-address \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --block-device-mappings "$BLOCK_DEVICES" \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}},{Key=Demo,Value=${DEMO_PREFIX}},{Key=Role,Value=storage-gateway},{Key=GatewayType,Value=${GATEWAY_TYPE}},{Key=cost-center,Value=architecting-pro}]" \
    "ResourceType=volume,Tags=[{Key=Name,Value=${INSTANCE_NAME}-root},{Key=Demo,Value=${DEMO_PREFIX}}]" \
  --output json \
  --query 'Instances[0].{InstanceId:InstanceId,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress}'

# =============================================================================
# STEP 5 — Verify the instance is running (wait ~1-2 min after launch)
# =============================================================================

# Check instance state
aws ec2 describe-instances \
  --region "$REGION" \
  --filters \
    "Name=tag:Name,Values=${INSTANCE_NAME}" \
    "Name=instance-state-name,Values=pending,running" \
  --query 'Reservations[*].Instances[*].{InstanceId:InstanceId,State:State.Name,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress,Type:InstanceType}' \
  --output table

# Check SSM reachability (wait ~2-3 min for SSM agent to register)
aws ssm describe-instance-information \
  --region "$REGION" \
  --filters "Key=tag:Name,Values=${INSTANCE_NAME}" \
  --query 'InstanceInformationList[*].{InstanceId:InstanceId,PingStatus:PingStatus,Platform:PlatformName}' \
  --output table

echo ""
echo "=== Next step: activate the gateway ==="
echo "    Get the public IP above and open:"
echo "    http://<PUBLIC_IP>/?activationRegion=${REGION}&gatewayType=${GATEWAY_TYPE}"

# =============================================================================
# STEP 6 — Assign disks after gateway activation
# Run these commands AFTER activating the gateway in the console or via CLI
#
# DISK LAYOUT:
#   /dev/sdf (nvme1n1) → cache / working storage
#   /dev/sdg (nvme2n1) → upload buffer
#
# First get the disk IDs from the gateway:
#   aws storagegateway list-local-disks \
#     --region "$REGION" \
#     --gateway-arn "<GATEWAY_ARN>" \
#     --query 'Disks[*].{DiskId:DiskId,Path:DiskPath,Node:DiskNode,SizeGB:DiskSizeInBytes,Alloc:DiskAllocationType}' \
#     --output table
#
# Then assign based on GATEWAY_TYPE:
# =============================================================================

# --- FILE_S3: assign sdf as cache ---
# DISK_ID_SDF="<DiskId for sdf/nvme1n1>"
# aws storagegateway add-cache \
#   --region "$REGION" \
#   --gateway-arn "<GATEWAY_ARN>" \
#   --disk-ids "$DISK_ID_SDF"

# --- VOLUME CACHED: assign sdf as cache, sdg as upload buffer ---
# DISK_ID_SDF="<DiskId for sdf/nvme1n1>"
# DISK_ID_SDG="<DiskId for sdg/nvme2n1>"
# aws storagegateway add-cache \
#   --region "$REGION" \
#   --gateway-arn "<GATEWAY_ARN>" \
#   --disk-ids "$DISK_ID_SDF"
# aws storagegateway add-upload-buffer \
#   --region "$REGION" \
#   --gateway-arn "<GATEWAY_ARN>" \
#   --disk-ids "$DISK_ID_SDG"

# --- VOLUME STORED: assign sdf as working storage, sdg as upload buffer ---
# DISK_ID_SDF="<DiskId for sdf/nvme1n1>"
# DISK_ID_SDG="<DiskId for sdg/nvme2n1>"
# aws storagegateway add-working-storage \
#   --region "$REGION" \
#   --gateway-arn "<GATEWAY_ARN>" \
#   --disk-ids "$DISK_ID_SDF"
# aws storagegateway add-upload-buffer \
#   --region "$REGION" \
#   --gateway-arn "<GATEWAY_ARN>" \
#   --disk-ids "$DISK_ID_SDG"

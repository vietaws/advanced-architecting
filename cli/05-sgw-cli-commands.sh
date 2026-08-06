#!/usr/bin/env bash
# =============================================================================
# Storage Gateway vs DataSync Demo — Instance Provisioning Commands
# File: cli/05-sgw-cli-commands.md (rendered as runnable bash)
# Region: us-east-1
# =============================================================================
# PREREQUISITES:
#   1. CFN stack "sgw-datasync-demo-network" deployed (cfn/03-network.yaml)
#   2. IAM role "ec2-instance-role" exists with SSM + S3 + EFS + FSx permissions
#   3. AWS CLI configured with sufficient permissions (EC2, SGW, DataSync)
#
# HOW TO USE:
#   - Copy individual commands as needed
#   - Replace ALL <PLACEHOLDER> values with your actual resource IDs
#   - Get IDs from CFN stack outputs:
#     aws cloudformation describe-stacks \
#       --stack-name sgw-datasync-demo-network \
#       --region us-east-1 \
#       --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' \
#       --output table
# =============================================================================

# =============================================================================
# STEP 0 — EXPORT COMMON VARIABLES
# Replace all values below with your actual resource IDs from CFN outputs
# =============================================================================

export REGION="us-east-1"
export DEMO_PREFIX="sgw-datasync-demo"

# From CFN stack outputs
export ONPREM_PUBLIC_SUBNET_1A="<OnPremPublicSubnet1aId>"   # e.g. subnet-0abc123
export ONPREM_VPC_ID="<OnPremVPCId>"                        # e.g. vpc-0abc123

# Security Group IDs (from CFN outputs)
export SG_NFS_SERVER="<OnPremNfsServerSGId>"
export SG_SMB_SERVER="<OnPremSmbServerSGId>"
export SG_SGW_APPLIANCE="<OnPremSGWApplianceSGId>"
export SG_DATASYNC_AGENT="<OnPremDataSyncAgentSGId>"
export SG_ISCSI_CLIENT="<OnPremISCSIClientSGId>"

# IAM Instance Profile (created outside this demo)
export IAM_INSTANCE_PROFILE="ec2-instance-role"

# AMI IDs (latest as of 2026-08-06, us-east-1)
# NOTE: Re-run the describe-images commands below to get the latest before launching
export AMI_AL2023_ARM="ami-0c6bc7d2a7c27e4d3"   # Amazon Linux 2023 ARM64 (t4g)
export AMI_WIN2022="ami-0f9c44e98edf38a2b"        # Windows Server 2022 Base (t3)
export AMI_SGW_FILE_S3="ami-0c2cf0a93df41ca5c"    # aws-storage-gateway-FILE_S3-2.1.10
export AMI_SGW_CLASSIC="ami-06ba9d823f80528b8"    # aws-storage-gateway-CLASSIC-3.2.8 (File+Volume)
export AMI_DATASYNC="ami-0f063e6b693a082c4"       # aws-datasync-2.0.1785850210.1

# =============================================================================
# STEP 0.1 — REFRESH AMI IDs (run before every demo to get latest)
# =============================================================================

# Latest Storage Gateway CLASSIC AMI (supports File Gateway + Volume Gateway)
aws ec2 describe-images \
  --region "$REGION" \
  --owners amazon \
  --filters \
    "Name=name,Values=aws-storage-gateway-CLASSIC-*" \
    "Name=state,Values=available" \
    "Name=architecture,Values=x86_64" \
  --query 'sort_by(Images, &CreationDate)[-1].{ImageId:ImageId,Name:Name,Date:CreationDate}' \
  --output table

# Latest DataSync Agent AMI
aws ec2 describe-images \
  --region "$REGION" \
  --owners amazon \
  --filters \
    "Name=name,Values=aws-datasync-*" \
    "Name=state,Values=available" \
    "Name=architecture,Values=x86_64" \
  --query 'sort_by(Images, &CreationDate)[-1].{ImageId:ImageId,Name:Name,Date:CreationDate}' \
  --output table

# Latest Amazon Linux 2023 ARM64 AMI
aws ssm get-parameter \
  --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64" \
  --region "$REGION" \
  --query 'Parameter.Value' \
  --output text

# Latest Windows Server 2022 Base AMI
aws ssm get-parameter \
  --name "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base" \
  --region "$REGION" \
  --query 'Parameter.Value' \
  --output text

# =============================================================================
# STEP 1 — NFS SERVER (t4g.micro, Amazon Linux 2023 ARM64)
# =============================================================================

aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_AL2023_ARM" \
  --instance-type t4g.micro \
  --subnet-id "$ONPREM_PUBLIC_SUBNET_1A" \
  --security-group-ids "$SG_NFS_SERVER" \
  --iam-instance-profile Name="$IAM_INSTANCE_PROFILE" \
  --associate-public-ip-address \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=op-nfs-server},{Key=Demo,Value=$DEMO_PREFIX},{Key=Role,Value=nfs-server}]" \
    "ResourceType=volume,Tags=[{Key=Name,Value=op-nfs-server-root},{Key=Demo,Value=$DEMO_PREFIX}]" \
  --user-data '#!/bin/bash
yum update -y
yum install -y nfs-utils
mkdir -p /data/nfs-share
chmod 777 /data/nfs-share
echo "/data/nfs-share 10.1.0.0/16(rw,sync,no_root_squash,no_all_squash)" >> /etc/exports
systemctl enable --now nfs-server
exportfs -rav
# Create demo test files
mkdir -p /data/nfs-share/{reports,data,compare-test,tmp}
for i in $(seq 1 20); do echo "Demo file $i - $(date)" > /data/nfs-share/reports/report-$i.txt; done
dd if=/dev/urandom bs=1M count=50 of=/data/nfs-share/data/sample-50mb.bin 2>/dev/null
for i in $(seq 1 100); do echo "Compare test $i" > /data/nfs-share/compare-test/file-$i.txt; done
echo "NFS server setup complete" > /var/log/demo-setup.log' \
  --output json \
  --query 'Instances[0].{InstanceId:InstanceId,PrivateIp:PrivateIpAddress}'

# =============================================================================
# STEP 2 — SMB SERVER (t4g.micro, Amazon Linux 2023 ARM64 + Samba)
# =============================================================================

aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_AL2023_ARM" \
  --instance-type t4g.micro \
  --subnet-id "$ONPREM_PUBLIC_SUBNET_1A" \
  --security-group-ids "$SG_SMB_SERVER" \
  --iam-instance-profile Name="$IAM_INSTANCE_PROFILE" \
  --associate-public-ip-address \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=op-smb-server},{Key=Demo,Value=$DEMO_PREFIX},{Key=Role,Value=smb-server}]" \
    "ResourceType=volume,Tags=[{Key=Name,Value=op-smb-server-root},{Key=Demo,Value=$DEMO_PREFIX}]" \
  --user-data '#!/bin/bash
yum update -y
yum install -y samba samba-client
mkdir -p /data/smb-share
chmod 777 /data/smb-share
# Configure Samba
cat > /etc/samba/smb.conf << SMBEOF
[global]
  workgroup = WORKGROUP
  security = user
  map to guest = Bad User
  log file = /var/log/samba/%m.log
  max log size = 50

[demo]
  path = /data/smb-share
  browsable = yes
  writable = yes
  guest ok = yes
  guest only = yes
  read only = no
  create mask = 0777
  directory mask = 0777
SMBEOF
systemctl enable --now smb nmb
# Create demo test files
mkdir -p /data/smb-share/{documents,finance,compare-test}
for i in $(seq 1 20); do echo "SMB Demo doc $i - $(date)" > /data/smb-share/documents/doc-$i.txt; done
for i in $(seq 1 10); do echo "Finance report $i" > /data/smb-share/finance/finance-$i.xlsx; done
echo "SMB server setup complete" > /var/log/demo-setup.log' \
  --output json \
  --query 'Instances[0].{InstanceId:InstanceId,PrivateIp:PrivateIpAddress}'

# =============================================================================
# STEP 3 — WINDOWS iSCSI CLIENT (t3.medium, Windows Server 2022)
# =============================================================================

aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_WIN2022" \
  --instance-type t3.medium \
  --subnet-id "$ONPREM_PUBLIC_SUBNET_1A" \
  --security-group-ids "$SG_ISCSI_CLIENT" \
  --iam-instance-profile Name="$IAM_INSTANCE_PROFILE" \
  --associate-public-ip-address \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --block-device-mappings '[{
    "DeviceName": "/dev/sda1",
    "Ebs": {
      "VolumeSize": 30,
      "VolumeType": "gp3",
      "DeleteOnTermination": true,
      "Encrypted": true
    }
  }]' \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=op-iscsi-client},{Key=Demo,Value=$DEMO_PREFIX},{Key=Role,Value=iscsi-client}]" \
    "ResourceType=volume,Tags=[{Key=Name,Value=op-iscsi-client-root},{Key=Demo,Value=$DEMO_PREFIX}]" \
  --user-data '<powershell>
# Enable iSCSI service (starts automatically on Windows Server 2022)
Set-Service -Name MSiSCSI -StartupType Automatic
Start-Service MSiSCSI

# Install CIFS/SMB client features (already built-in on Windows Server)
# Enable SSM Agent (pre-installed on Windows Server 2022 AMI)
Set-Content -Path "C:\demo-setup.log" -Value "Windows iSCSI client setup complete - $(Get-Date)"
</powershell>' \
  --output json \
  --query 'Instances[0].{InstanceId:InstanceId,PrivateIp:PrivateIpAddress}'

# =============================================================================
# STEP 4A — STORAGE GATEWAY APPLIANCE — ON-DEMAND (m6i.xlarge)
# =============================================================================
# NOTE: SGW CLASSIC AMI supports both File Gateway (NFS+SMB) and Volume Gateway (iSCSI)
# The appliance REQUIRES two EBS disks:
#   - Root disk:  80 GB gp3  (OS + gateway software)
#   - Cache disk: 150 GB gp3 (local cache for File/Volume Gateway, MUST be attached at launch)

aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_SGW_CLASSIC" \
  --instance-type m6i.xlarge \
  --subnet-id "$ONPREM_PUBLIC_SUBNET_1A" \
  --security-group-ids "$SG_SGW_APPLIANCE" \
  --iam-instance-profile Name="$IAM_INSTANCE_PROFILE" \
  --associate-public-ip-address \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --block-device-mappings '[
    {
      "DeviceName": "/dev/xvda",
      "Ebs": {
        "VolumeSize": 80,
        "VolumeType": "gp3",
        "DeleteOnTermination": true,
        "Encrypted": true
      }
    },
    {
      "DeviceName": "/dev/xvdf",
      "Ebs": {
        "VolumeSize": 150,
        "VolumeType": "gp3",
        "DeleteOnTermination": true,
        "Encrypted": true
      }
    }
  ]' \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=op-sgw-appliance},{Key=Demo,Value=$DEMO_PREFIX},{Key=Role,Value=storage-gateway},{Key=PricingModel,Value=on-demand}]" \
    "ResourceType=volume,Tags=[{Key=Name,Value=op-sgw-root},{Key=Demo,Value=$DEMO_PREFIX}]" \
  --output json \
  --query 'Instances[0].{InstanceId:InstanceId,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress}'

# =============================================================================
# STEP 4B — STORAGE GATEWAY APPLIANCE — SPOT (m6i.xlarge)
# =============================================================================
# Current spot prices (2026-08-06):
#   us-east-1a: $0.1119/hr (vs $0.1920 on-demand = 42% savings)
#   us-east-1b: $0.0949/hr (cheapest AZ, but demo subnets are in 1a)
#   us-east-1c: $0.0821/hr (cheapest, but not in demo VPC)
#
# IMPORTANT: If Spot is interrupted, the SGW appliance goes offline and the
# gateway enters "OFFLINE" state. You must restart from scratch (re-activate).
# Low risk during business hours (~5% interruption rate for m6i.xlarge us-east-1a).
# Set max price to on-demand ($0.1920) so spot is used when available but
# on-demand takes over if spot price spikes above threshold.

aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_SGW_CLASSIC" \
  --instance-type m6i.xlarge \
  --subnet-id "$ONPREM_PUBLIC_SUBNET_1A" \
  --security-group-ids "$SG_SGW_APPLIANCE" \
  --iam-instance-profile Name="$IAM_INSTANCE_PROFILE" \
  --associate-public-ip-address \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --instance-market-options '{
    "MarketType": "spot",
    "SpotOptions": {
      "MaxPrice": "0.1920",
      "SpotInstanceType": "one-time",
      "InstanceInterruptionBehavior": "terminate"
    }
  }' \
  --block-device-mappings '[
    {
      "DeviceName": "/dev/xvda",
      "Ebs": {
        "VolumeSize": 80,
        "VolumeType": "gp3",
        "DeleteOnTermination": true,
        "Encrypted": true
      }
    },
    {
      "DeviceName": "/dev/xvdf",
      "Ebs": {
        "VolumeSize": 150,
        "VolumeType": "gp3",
        "DeleteOnTermination": true,
        "Encrypted": true
      }
    }
  ]' \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=op-sgw-appliance},{Key=Demo,Value=$DEMO_PREFIX},{Key=Role,Value=storage-gateway},{Key=PricingModel,Value=spot}]" \
    "ResourceType=volume,Tags=[{Key=Name,Value=op-sgw-root},{Key=Demo,Value=$DEMO_PREFIX}]" \
  --output json \
  --query 'Instances[0].{InstanceId:InstanceId,SpotRequestId:SpotInstanceRequestId,PrivateIp:PrivateIpAddress}'

# =============================================================================
# STEP 5A — DATASYNC AGENT — ON-DEMAND (m6a.2xlarge)
# =============================================================================

aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_DATASYNC" \
  --instance-type m6a.2xlarge \
  --subnet-id "$ONPREM_PUBLIC_SUBNET_1A" \
  --security-group-ids "$SG_DATASYNC_AGENT" \
  --iam-instance-profile Name="$IAM_INSTANCE_PROFILE" \
  --associate-public-ip-address \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --block-device-mappings '[{
    "DeviceName": "/dev/xvda",
    "Ebs": {
      "VolumeSize": 80,
      "VolumeType": "gp3",
      "DeleteOnTermination": true,
      "Encrypted": true
    }
  }]' \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=op-datasync-agent},{Key=Demo,Value=$DEMO_PREFIX},{Key=Role,Value=datasync-agent},{Key=PricingModel,Value=on-demand}]" \
    "ResourceType=volume,Tags=[{Key=Name,Value=op-datasync-agent-root},{Key=Demo,Value=$DEMO_PREFIX}]" \
  --output json \
  --query 'Instances[0].{InstanceId:InstanceId,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress}'

# =============================================================================
# STEP 5B — DATASYNC AGENT — SPOT (m6a.2xlarge)
# =============================================================================
# Current spot prices (2026-08-06):
#   us-east-1a: $0.1600/hr (vs $0.3456 on-demand = 54% savings)
#   us-east-1f: $0.1426/hr (cheapest AZ for m6a.2xlarge)
#   us-east-1d: $0.1524/hr

aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_DATASYNC" \
  --instance-type m6a.2xlarge \
  --subnet-id "$ONPREM_PUBLIC_SUBNET_1A" \
  --security-group-ids "$SG_DATASYNC_AGENT" \
  --iam-instance-profile Name="$IAM_INSTANCE_PROFILE" \
  --associate-public-ip-address \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --instance-market-options '{
    "MarketType": "spot",
    "SpotOptions": {
      "MaxPrice": "0.3456",
      "SpotInstanceType": "one-time",
      "InstanceInterruptionBehavior": "terminate"
    }
  }' \
  --block-device-mappings '[{
    "DeviceName": "/dev/xvda",
    "Ebs": {
      "VolumeSize": 80,
      "VolumeType": "gp3",
      "DeleteOnTermination": true,
      "Encrypted": true
    }
  }]' \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=op-datasync-agent},{Key=Demo,Value=$DEMO_PREFIX},{Key=Role,Value=datasync-agent},{Key=PricingModel,Value=spot}]" \
    "ResourceType=volume,Tags=[{Key=Name,Value=op-datasync-agent-root},{Key=Demo,Value=$DEMO_PREFIX}]" \
  --output json \
  --query 'Instances[0].{InstanceId:InstanceId,SpotRequestId:SpotInstanceRequestId,PrivateIp:PrivateIpAddress}'

# =============================================================================
# STEP 6 — VERIFY ALL INSTANCES ARE RUNNING AND SSM-REACHABLE
# =============================================================================

# List all demo instances
aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=tag:Demo,Values=$DEMO_PREFIX" \
  --query 'Reservations[*].Instances[*].{Name:Tags[?Key==`Name`]|[0].Value,InstanceId:InstanceId,State:State.Name,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress,Type:InstanceType}' \
  --output table

# Verify SSM connectivity for all Linux instances (wait ~2-3 min after launch)
aws ssm describe-instance-information \
  --region "$REGION" \
  --filters "Key=tag:Demo,Values=$DEMO_PREFIX" \
  --query 'InstanceInformationList[*].{InstanceId:InstanceId,PingStatus:PingStatus,Platform:PlatformName}' \
  --output table

# =============================================================================
# STEP 7 — ACTIVATE STORAGE GATEWAY
# =============================================================================
# The gateway must be activated before use. Two methods:
#
# METHOD A: Via AWS Console (recommended for demo — visual and clear)
#   1. Go to Storage Gateway console → Create gateway
#   2. Choose gateway type: "Amazon S3 File Gateway" or "Volume Gateway"
#   3. For hosting: "Amazon EC2"
#   4. Enter the PUBLIC IP of op-sgw-appliance as the activation URL
#   5. The console fetches an activation key automatically
#   6. Complete gateway setup: name, timezone, cache disk selection
#
# METHOD B: Via CLI (headless / scripted)

# 7a. Get activation key from the appliance (replace with actual public IP)
export SGW_PUBLIC_IP="<op-sgw-appliance-public-ip>"

ACTIVATION_KEY=$(curl -s \
  "http://${SGW_PUBLIC_IP}/?activationRegion=${REGION}&gatewayType=FILE_S3&no_redirect" \
  | grep -oP 'key=[^&"]+' | cut -d= -f2)

echo "Activation Key: $ACTIVATION_KEY"

# 7b. Activate the gateway
aws storagegateway activate-gateway \
  --region "$REGION" \
  --activation-key "$ACTIVATION_KEY" \
  --gateway-name "op-sgw-appliance" \
  --gateway-timezone "GMT+7:00" \
  --gateway-region "$REGION" \
  --gateway-type "FILE_S3" \
  --output json

# 7c. Get the gateway ARN (save this for file share creation)
export GATEWAY_ARN=$(aws storagegateway list-gateways \
  --region "$REGION" \
  --query 'Gateways[?GatewayName==`op-sgw-appliance`].GatewayARN' \
  --output text)
echo "Gateway ARN: $GATEWAY_ARN"

# 7d. List local disks on the appliance (find the 150 GB cache disk to assign)
aws storagegateway list-local-disks \
  --region "$REGION" \
  --gateway-arn "$GATEWAY_ARN" \
  --output table

# 7e. Assign the 150 GB disk as the cache disk (replace DiskId with actual value)
export CACHE_DISK_ID="<disk-id-from-step-7d>"  # e.g. /dev/xvdf

aws storagegateway add-cache \
  --region "$REGION" \
  --gateway-arn "$GATEWAY_ARN" \
  --disk-ids "$CACHE_DISK_ID"

# =============================================================================
# STEP 8 — ACTIVATE DATASYNC AGENT
# =============================================================================
# METHOD A: Via AWS Console (recommended)
#   1. Go to DataSync console → Agents → Create agent
#   2. Hypervisor: Amazon EC2
#   3. Enter the PUBLIC IP of op-datasync-agent in the activation field
#   4. Choose VPC endpoint or public service endpoint
#   5. Name: op-datasync-agent → Activate
#
# METHOD B: Via CLI

export DATASYNC_PUBLIC_IP="<op-datasync-agent-public-ip>"

# Get activation key from the agent
DATASYNC_KEY=$(curl -s \
  "http://${DATASYNC_PUBLIC_IP}/?activationRegion=${REGION}&no_redirect")

echo "DataSync Activation Key: $DATASYNC_KEY"

aws datasync create-agent \
  --region "$REGION" \
  --activation-key "$DATASYNC_KEY" \
  --agent-name "op-datasync-agent" \
  --tags Key=Demo,Value="$DEMO_PREFIX" \
  --output json

# =============================================================================
# STEP 9 — CHECK SPOT INTERRUPTION RISK (run before the demo)
# =============================================================================
# Check current spot prices across AZs to gauge interruption risk

aws ec2 describe-spot-price-history \
  --region "$REGION" \
  --instance-types m6i.xlarge m6a.2xlarge \
  --product-descriptions "Linux/UNIX" \
  --query 'sort_by(SpotPriceHistory, &SpotPrice)[*].[InstanceType,AvailabilityZone,SpotPrice]' \
  --output table

# Check interruption frequency scores (via EC2 Spot Advisor API — browser only)
# https://spot-price.s3.amazonaws.com/spot.js
# Look for m6i.xlarge and m6a.2xlarge in us-east-1 — target <10% interruption frequency

# =============================================================================
# STEP 10 — DEMO CLEANUP (run after the demo to stop billing)
# =============================================================================

# 10a. Get all demo instance IDs
INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=tag:Demo,Values=$DEMO_PREFIX" "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text | tr '\n' ' ')

echo "Instances to terminate: $INSTANCE_IDS"

# 10b. Terminate all demo EC2 instances
aws ec2 terminate-instances \
  --region "$REGION" \
  --instance-ids $INSTANCE_IDS

# 10c. Delete Storage Gateway (run BEFORE CFN stack deletion)
aws storagegateway delete-gateway \
  --region "$REGION" \
  --gateway-arn "$GATEWAY_ARN"

# 10d. Delete FSx file system (get FileSystemId from console or CFN)
# WARNING: This permanently deletes all FSx data
# aws fsx delete-file-system \
#   --region "$REGION" \
#   --file-system-id "<fsx-file-system-id>"

# 10e. Empty S3 bucket (required before CFN stack deletion)
export S3_BUCKET="${DEMO_PREFIX}-$(aws sts get-caller-identity --query Account --output text)"
aws s3 rm "s3://${S3_BUCKET}" --recursive --region "$REGION"

# 10f. Delete CFN stack (removes VPCs, subnets, SGs, NACLs, EFS, S3 bucket, VPC endpoints)
aws cloudformation delete-stack \
  --region "$REGION" \
  --stack-name sgw-datasync-demo-network

# Monitor deletion
aws cloudformation wait stack-delete-complete \
  --region "$REGION" \
  --stack-name sgw-datasync-demo-network && echo "Stack deleted successfully"

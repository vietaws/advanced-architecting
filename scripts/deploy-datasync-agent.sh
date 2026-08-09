#!/usr/bin/env bash

# =============================================================================
# INPUT VARIABLES — fill these in before running
# =============================================================================

export REGION="us-east-1"
export DEMO_PREFIX="sgw-datasync-demo"

# OnPrem VPC networking (from CFN stack outputs)
export VPC_ID="VPC_ID"               # e.g. vpc-0abc1234567890abc
export SUBNET_ID="SUBNET_ID"          # e.g. subnet-0abc1234567890abc
export SECURITY_GROUP_ID="SECURITY_GROUP_ID"  # e.g. sg-0abc1234567890abc

# DataSync Agent AMI — leave empty to auto-resolve from SSM (recommended)
# Or set explicitly to pin a specific version: e.g. ami-0f063e6b693a082c4
# Document: https://docs.aws.amazon.com/datasync/latest/userguide/deploy-agents.html#ec2-deploy-agent
# Agent Requirement: https://docs.aws.amazon.com/datasync/latest/userguide/agent-requirements.html
export AMI_ID=""

# =============================================================================
# FIXED CONFIG — no changes needed below this line
# =============================================================================

export INSTANCE_TYPE="m6a.2xlarge" # or m5.2xlarge
export IAM_INSTANCE_PROFILE="ec2-instance-role"
export INSTANCE_NAME="op-datasync-agent"

# =============================================================================
# STEP 1 — Resolve the latest DataSync Agent AMI via SSM
# Overrides AMI_ID only if it was left empty above
# =============================================================================

if [[ -z "$AMI_ID" ]]; then
  AMI_ID=$(aws ssm get-parameter \
    --name "/aws/service/datasync/ami" \
    --region "$REGION" \
    --query 'Parameter.Value' \
    --output text)
  echo "Resolved DataSync AMI from SSM: $AMI_ID"
else
  echo "Using pinned AMI: $AMI_ID"
fi

# =============================================================================
# STEP 2 — Launch the DataSync Agent EC2 instance
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
    "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}},{Key=Demo,Value=${DEMO_PREFIX}},{Key=Role,Value=datasync-agent},{Key=cost-center,Value=architecting-pro}]" \
    "ResourceType=volume,Tags=[{Key=Name,Value=${INSTANCE_NAME}-root},{Key=Demo,Value=${DEMO_PREFIX}},{Key=cost-center,Value=architecting-pro}]" \
  --output json \
  --query 'Instances[0].{InstanceId:InstanceId,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress}'

# =============================================================================
# STEP 3 — Verify the instance is running (wait ~1-2 min after launch)
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

#!/usr/bin/env bash
# =============================================================================
# 02-addons-eksctl.sh — Install EKS add-ons using eksctl for IRSA role creation
#
# BACKUP / REFERENCE ONLY
# Primary script: 02-addons.sh (creates IAM roles via aws cli first)
#
# Known issue: eksctl create iamserviceaccount silently skips role creation
# if the K8s ServiceAccount already exists, leaving the addon without a valid
# role ARN and causing it to hang in CREATING state indefinitely.
# Use 02-addons.sh instead.
#
# Run AFTER: EKS cluster and node group are created (Phase 2)
#
# Usage:
#   export AWS_ACCOUNT_ID=123456789012
#   ./eks-setup/02-addons-eksctl.sh
# =============================================================================
set -euo pipefail

export AWS_PAGER=""

CLUSTER_NAME="demo-cluster"
REGION="ap-southeast-1"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
ALB_CHART_VERSION="3.4.3"
# Check latest version: https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller

# Helper: wait for addon to reach ACTIVE state
wait_addon() {
  echo -n "  Waiting for $1 to become ACTIVE... "
  aws eks wait addon-active \
    --cluster-name "${CLUSTER_NAME}" \
    --addon-name   "$1" \
    --region       "${REGION}"
  echo "OK"
}

echo "============================================================"
echo "  Installing EKS add-ons (eksctl variant)"
echo "  Cluster: ${CLUSTER_NAME} | Region: ${REGION}"
echo "============================================================"

# ── 1. kube-proxy ─────────────────────────────────────────────────────────────
echo ""
echo "[1/5] kube-proxy..."
aws eks create-addon \
  --cluster-name "${CLUSTER_NAME}" --addon-name kube-proxy \
  --resolve-conflicts OVERWRITE --region "${REGION}" 2>/dev/null || \
aws eks update-addon \
  --cluster-name "${CLUSTER_NAME}" --addon-name kube-proxy \
  --resolve-conflicts OVERWRITE --region "${REGION}"
wait_addon "kube-proxy"
echo "[1/5] kube-proxy OK"

# ── 2. CoreDNS ────────────────────────────────────────────────────────────────
echo ""
echo "[2/5] CoreDNS..."
aws eks create-addon \
  --cluster-name "${CLUSTER_NAME}" --addon-name coredns \
  --resolve-conflicts OVERWRITE --region "${REGION}" 2>/dev/null || \
aws eks update-addon \
  --cluster-name "${CLUSTER_NAME}" --addon-name coredns \
  --resolve-conflicts OVERWRITE --region "${REGION}"
wait_addon "coredns"
echo "[2/5] CoreDNS OK"

# ── 3. EBS CSI Driver ─────────────────────────────────────────────────────────
echo ""
echo "[3/5] EBS CSI driver..."

eksctl create iamserviceaccount \
  --cluster   "${CLUSTER_NAME}" \
  --region    "${REGION}" \
  --namespace kube-system \
  --name      ebs-csi-controller-sa \
  --role-name eks-ebs-csi-driver-role \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --override-existing-serviceaccounts

aws eks create-addon \
  --cluster-name "${CLUSTER_NAME}" \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/eks-ebs-csi-driver-role" \
  --resolve-conflicts OVERWRITE \
  --region "${REGION}" 2>/dev/null || \
aws eks update-addon \
  --cluster-name "${CLUSTER_NAME}" \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/eks-ebs-csi-driver-role" \
  --resolve-conflicts OVERWRITE \
  --region "${REGION}"

wait_addon "aws-ebs-csi-driver"
echo "[3/5] EBS CSI OK"

# ── 4. EFS CSI Driver ─────────────────────────────────────────────────────────
echo ""
echo "[4/5] EFS CSI driver..."

EFS_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AmazonEFSCSIDriverPolicy"

aws iam create-policy \
  --policy-name AmazonEFSCSIDriverPolicy \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["elasticfilesystem:DescribeAccessPoints","elasticfilesystem:DescribeFileSystems","elasticfilesystem:DescribeMountTargets","ec2:DescribeAvailabilityZones"],"Resource":"*"},{"Effect":"Allow","Action":["elasticfilesystem:CreateAccessPoint"],"Resource":"*","Condition":{"StringLike":{"aws:RequestTag/efs.csi.aws.com/cluster":"true"}}},{"Effect":"Allow","Action":["elasticfilesystem:TagResource"],"Resource":"*","Condition":{"StringLike":{"aws:ResourceTag/efs.csi.aws.com/cluster":"true"}}},{"Effect":"Allow","Action":"elasticfilesystem:DeleteAccessPoint","Resource":"*","Condition":{"StringEquals":{"aws:ResourceTag/efs.csi.aws.com/cluster":"true"}}}]}' \
  2>/dev/null || echo "  (EFS policy already exists)"

eksctl create iamserviceaccount \
  --cluster   "${CLUSTER_NAME}" \
  --region    "${REGION}" \
  --namespace kube-system \
  --name      efs-csi-controller-sa \
  --role-name eks-efs-csi-driver-role \
  --attach-policy-arn "${EFS_POLICY_ARN}" \
  --approve \
  --override-existing-serviceaccounts

aws eks create-addon \
  --cluster-name "${CLUSTER_NAME}" \
  --addon-name aws-efs-csi-driver \
  --service-account-role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/eks-efs-csi-driver-role" \
  --resolve-conflicts OVERWRITE \
  --region "${REGION}" 2>/dev/null || \
aws eks update-addon \
  --cluster-name "${CLUSTER_NAME}" \
  --addon-name aws-efs-csi-driver \
  --service-account-role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/eks-efs-csi-driver-role" \
  --resolve-conflicts OVERWRITE \
  --region "${REGION}"

wait_addon "aws-efs-csi-driver"
echo "[4/5] EFS CSI OK"

# ── 5. AWS Load Balancer Controller ──────────────────────────────────────────
echo ""
echo "[5/5] AWS Load Balancer Controller..."

ALB_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document "file://${SCRIPT_DIR}/iam/alb-controller-policy.json" \
  2>/dev/null || echo "  (ALB policy already exists)"

eksctl create iamserviceaccount \
  --cluster   "${CLUSTER_NAME}" \
  --region    "${REGION}" \
  --namespace kube-system \
  --name      aws-load-balancer-controller \
  --role-name eks-alb-controller-role \
  --attach-policy-arn "${ALB_POLICY_ARN}" \
  --approve \
  --override-existing-serviceaccounts

helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update eks

VPC_ID="$(aws eks describe-cluster \
  --name "${CLUSTER_NAME}" --region "${REGION}" \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text)"

# Image registry per region: https://docs.aws.amazon.com/eks/latest/userguide/add-ons-images.html
# ap-southeast-1 registry: 602401143452.dkr.ecr.ap-southeast-1.amazonaws.com
ECR_REGISTRY="602401143452.dkr.ecr.${REGION}.amazonaws.com"

helm upgrade --install aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  --namespace kube-system \
  --version "${ALB_CHART_VERSION}" \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region="${REGION}" \
  --set vpcId="${VPC_ID}" \
  --set image.repository="${ECR_REGISTRY}/amazon/aws-load-balancer-controller" \
  --wait

echo "[5/5] AWS Load Balancer Controller OK"

echo ""
echo "============================================================"
echo "  All add-ons installed successfully"
echo "  Next: ./eks-setup/03-oidc-irsa.sh"
echo "============================================================"

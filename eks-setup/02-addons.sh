#!/usr/bin/env bash
# =============================================================================
# 02-addons.sh — Install EKS add-ons and AWS Load Balancer Controller
#
# Run AFTER: EKS cluster and node group are created (Phase 2)
#
# IAM roles created by this script:
#   eks-ebs-csi-driver-role  — for EBS CSI driver
#   eks-efs-csi-driver-role  — for EFS CSI driver
#   eks-alb-controller-role  — for AWS Load Balancer Controller
#
# Usage:
#   export AWS_ACCOUNT_ID=123456789012
#   ./eks-setup/02-addons.sh
# =============================================================================
set -euo pipefail

# Disable AWS CLI pager so output is not piped through 'less'
export AWS_PAGER=""

CLUSTER_NAME="demo-cluster"
REGION="ap-southeast-1"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
ALB_CHART_VERSION="3.4.3"
# Check latest version: https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller

# ── OIDC provider ID (needed for role trust policies) ────────────────────────
OIDC_ID="$(aws eks describe-cluster \
  --name "${CLUSTER_NAME}" --region "${REGION}" \
  --query 'cluster.identity.oidc.issuer' --output text \
  | sed 's|https://||')"

OIDC_PROVIDER="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ID}"

echo "============================================================"
echo "  Installing EKS add-ons"
echo "  Cluster:  ${CLUSTER_NAME}"
echo "  Region:   ${REGION}"
echo "  OIDC ID:  ${OIDC_ID}"
echo "============================================================"

# ── Helper: create IAM role with OIDC trust policy ───────────────────────────
# Usage: create_iam_role <role-name> <namespace> <serviceaccount>
create_iam_role() {
  local ROLE_NAME="$1"
  local NAMESPACE="$2"
  local SA_NAME="$3"

  local TRUST_POLICY
  TRUST_POLICY="{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Federated\":\"${OIDC_PROVIDER}\"},\"Action\":\"sts:AssumeRoleWithWebIdentity\",\"Condition\":{\"StringEquals\":{\"${OIDC_ID}:sub\":\"system:serviceaccount:${NAMESPACE}:${SA_NAME}\",\"${OIDC_ID}:aud\":\"sts.amazonaws.com\"}}}]}"

  if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
    echo "  IAM role already exists: ${ROLE_NAME}"
  else
    aws iam create-role \
      --role-name "${ROLE_NAME}" \
      --assume-role-policy-document "${TRUST_POLICY}"
    echo "  Created IAM role: ${ROLE_NAME}"
  fi
}

# ── Helper: link existing IAM role to K8s ServiceAccount via eksctl ──────────
# Usage: link_serviceaccount <namespace> <serviceaccount> <role-name>
link_serviceaccount() {
  local NAMESPACE="$1"
  local SA_NAME="$2"
  local ROLE_NAME="$3"
  local ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

  eksctl create iamserviceaccount \
    --cluster   "${CLUSTER_NAME}" \
    --region    "${REGION}" \
    --namespace "${NAMESPACE}" \
    --name      "${SA_NAME}" \
    --attach-role-arn "${ROLE_ARN}" \
    --approve \
    --override-existing-serviceaccounts
  echo "  Linked ServiceAccount ${SA_NAME} → ${ROLE_NAME}"
}

# ── Helper: wait for addon ACTIVE ────────────────────────────────────────────
wait_addon() {
  echo -n "  Waiting for $1 to become ACTIVE... "
  aws eks wait addon-active \
    --cluster-name "${CLUSTER_NAME}" \
    --addon-name   "$1" \
    --region       "${REGION}"
  echo "OK"
}

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
echo "[1/5] kube-proxy OK ✅"

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
echo "[2/5] CoreDNS OK ✅"

# ── 3. EBS CSI Driver ─────────────────────────────────────────────────────────
echo ""
echo "[3/5] EBS CSI driver..."

# Step 1: create IAM role via aws cli
create_iam_role "eks-ebs-csi-driver-role" "kube-system" "ebs-csi-controller-sa"
aws iam attach-role-policy \
  --role-name eks-ebs-csi-driver-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  2>/dev/null || true

# Step 2: link to K8s ServiceAccount
link_serviceaccount "kube-system" "ebs-csi-controller-sa" "eks-ebs-csi-driver-role"

# Step 3: install addon pointing to the role
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
echo "[3/5] EBS CSI OK ✅"

# ── 4. EFS CSI Driver ─────────────────────────────────────────────────────────
echo ""
echo "[4/5] EFS CSI driver..."

# Step 1: create custom EFS policy
EFS_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AmazonEFSCSIDriverPolicy"
aws iam create-policy \
  --policy-name AmazonEFSCSIDriverPolicy \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["elasticfilesystem:DescribeAccessPoints","elasticfilesystem:DescribeFileSystems","elasticfilesystem:DescribeMountTargets","ec2:DescribeAvailabilityZones"],"Resource":"*"},{"Effect":"Allow","Action":["elasticfilesystem:CreateAccessPoint"],"Resource":"*","Condition":{"StringLike":{"aws:RequestTag/efs.csi.aws.com/cluster":"true"}}},{"Effect":"Allow","Action":["elasticfilesystem:TagResource"],"Resource":"*","Condition":{"StringLike":{"aws:ResourceTag/efs.csi.aws.com/cluster":"true"}}},{"Effect":"Allow","Action":"elasticfilesystem:DeleteAccessPoint","Resource":"*","Condition":{"StringEquals":{"aws:ResourceTag/efs.csi.aws.com/cluster":"true"}}}]}' \
  2>/dev/null || echo "  (EFS policy already exists)"

# Step 2: create IAM role via aws cli
create_iam_role "eks-efs-csi-driver-role" "kube-system" "efs-csi-controller-sa"
aws iam attach-role-policy \
  --role-name eks-efs-csi-driver-role \
  --policy-arn "${EFS_POLICY_ARN}" \
  2>/dev/null || true

# Step 3: link to K8s ServiceAccount
link_serviceaccount "kube-system" "efs-csi-controller-sa" "eks-efs-csi-driver-role"

# Step 4: install addon pointing to the role
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
echo "[4/5] EFS CSI OK ✅"

# ── 5. AWS Load Balancer Controller ──────────────────────────────────────────
echo ""
echo "[5/5] AWS Load Balancer Controller..."

# Step 1: create ALB policy
ALB_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document "file://${SCRIPT_DIR}/iam/alb-controller-policy.json" \
  2>/dev/null || echo "  (ALB policy already exists)"

# Step 2: create IAM role via aws cli
create_iam_role "eks-alb-controller-role" "kube-system" "aws-load-balancer-controller"
aws iam attach-role-policy \
  --role-name eks-alb-controller-role \
  --policy-arn "${ALB_POLICY_ARN}" \
  2>/dev/null || true

# Step 3: link to K8s ServiceAccount
link_serviceaccount "kube-system" "aws-load-balancer-controller" "eks-alb-controller-role"

# Step 4: install via Helm
# Always do a clean install to avoid broken upgrade state
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true

# Clean up CRDs from any previous install
kubectl delete crd ingressclassparams.elbv2.k8s.aws 2>/dev/null || true
kubectl delete crd targetgroupbindings.elbv2.k8s.aws 2>/dev/null || true

helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update eks

VPC_ID="$(aws eks describe-cluster \
  --name "${CLUSTER_NAME}" --region "${REGION}" \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text)"

# Image registry per region: https://docs.aws.amazon.com/eks/latest/userguide/add-ons-images.html
# ap-southeast-1 registry: 602401143452.dkr.ecr.ap-southeast-1.amazonaws.com
ECR_REGISTRY="602401143452.dkr.ecr.${REGION}.amazonaws.com"

helm install aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  --namespace kube-system \
  --version "${ALB_CHART_VERSION}" \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region="${REGION}" \
  --set vpcId="${VPC_ID}" \
  --set image.repository="${ECR_REGISTRY}/amazon/aws-load-balancer-controller" \
  --set replicaCount=1

echo "  Waiting for ALB controller deployment..."
kubectl rollout status deployment/aws-load-balancer-controller \
  -n kube-system --timeout=120s

echo "[5/5] AWS Load Balancer Controller OK"

echo ""
echo "============================================================"
echo "  All add-ons installed successfully"
echo "  Next: ./eks-setup/03-oidc-irsa.sh"
echo "============================================================"

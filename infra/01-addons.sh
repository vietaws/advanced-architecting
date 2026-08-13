#!/usr/bin/env bash
# =============================================================================
# IAM roles created by this script (via eksctl create iamserviceaccount):
#   eks-ebs-csi-driver-role  — EBS CSI driver      (AmazonEBSCSIDriverPolicy)
#   eks-efs-csi-driver-role  — EFS CSI driver      (AmazonEFSCSIDriverPolicy)
#   eks-alb-controller-role  — ALB Controller      (AWSLoadBalancerControllerIAMPolicy)
#
# =============================================================================
set -euo pipefail
export AWS_PAGER=""

CLUSTER_NAME="demo-cluster"
REGION="ap-southeast-1"
NAMESPACE_SYSTEM="kube-system"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"

ALB_CHART_VERSION="3.5.0"
# Check latest: https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller

# Image registry per region: https://docs.aws.amazon.com/eks/latest/userguide/add-ons-images.html
ECR_REGISTRY="602401143452.dkr.ecr.${REGION}.amazonaws.com"

echo "============================================================"
echo "  Installing EKS add-ons"
echo "  Cluster: ${CLUSTER_NAME} | Region: ${REGION}"
echo "============================================================"

# ── Helper: wait for addon to reach ACTIVE ───────────────────────────────────
wait_addon() {
  echo -n "  Waiting for $1 to become ACTIVE... "
  aws eks wait addon-active \
    --cluster-name "${CLUSTER_NAME}" \
    --addon-name   "$1" \
    --region       "${REGION}"
  echo "OK ✅"
}

# ── Helper: create iamserviceaccount via eksctl ───────────────────────────────
# Deletes the K8s ServiceAccount first to prevent eksctl silently skipping
# role creation when the SA already exists from a previous run.
create_irsa() {
  local SA_NAME="$1"
  local ROLE_NAME="$2"
  local POLICY_ARN="$3"

  echo "  Removing existing ServiceAccount ${SA_NAME} (if any)..."
  kubectl delete serviceaccount "${SA_NAME}" \
    -n "${NAMESPACE_SYSTEM}" --ignore-not-found 2>/dev/null || true

  eksctl create iamserviceaccount \
    --cluster        "${CLUSTER_NAME}" \
    --region         "${REGION}" \
    --namespace      "${NAMESPACE_SYSTEM}" \
    --name           "${SA_NAME}" \
    --role-name      "${ROLE_NAME}" \
    --attach-policy-arn "${POLICY_ARN}" \
    --approve \
    --override-existing-serviceaccounts

  echo "  Created IAM role ${ROLE_NAME} → ServiceAccount ${SA_NAME} ✅"
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

create_irsa \
  "ebs-csi-controller-sa" \
  "eks-ebs-csi-driver-role" \
  "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"

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

create_irsa \
  "efs-csi-controller-sa" \
  "eks-efs-csi-driver-role" \
  "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"

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

# Create IAM policy from local file (not AWS managed)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALB_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document "file://${SCRIPT_DIR}/iam/alb-controller-policy.json" \
  2>/dev/null || echo "  (ALB policy already exists)"

create_irsa \
  "aws-load-balancer-controller" \
  "eks-alb-controller-role" \
  "${ALB_POLICY_ARN}"

# Clean install — remove any previous broken release and stale CRDs
helm uninstall aws-load-balancer-controller -n "${NAMESPACE_SYSTEM}" 2>/dev/null || true
kubectl delete crd ingressclassparams.elbv2.k8s.aws 2>/dev/null || true
kubectl delete crd targetgroupbindings.elbv2.k8s.aws 2>/dev/null || true

helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update eks

VPC_ID="$(aws eks describe-cluster \
  --name "${CLUSTER_NAME}" --region "${REGION}" \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text)"

helm install aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  --namespace "${NAMESPACE_SYSTEM}" \
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
  -n "${NAMESPACE_SYSTEM}" --timeout=120s

echo "[5/5] AWS Load Balancer Controller OK ✅"

echo ""
echo "============================================================"
echo "  All add-ons installed successfully"
echo "============================================================"

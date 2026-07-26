#!/usr/bin/env bash
# =============================================================================
# 02-addons.sh — Install EKS add-ons and AWS Load Balancer Controller
#
# Run AFTER: 01-cluster.sh
#
# What this installs:
#   1. kube-proxy           (EKS managed add-on)
#   2. CoreDNS              (EKS managed add-on)
#   3. Amazon EBS CSI       (EKS managed add-on, needs IRSA)
#   4. Amazon EFS CSI       (EKS managed add-on, needs IRSA)
#   5. AWS Load Balancer Controller  (Helm chart, needs IRSA)
#
# Usage:
#   chmod +x infra/02-addons.sh
#   AWS_ACCOUNT_ID=123456789012 ./infra/02-addons.sh
# =============================================================================
set -euo pipefail

# ── Variables ─────────────────────────────────────────────────────────────────
CLUSTER_NAME="demo-cluster"
REGION="ap-southeast-1"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"

# Helm chart versions (pin for reproducibility)
ALB_CHART_VERSION="1.8.1"

echo "============================================================"
echo "  Installing EKS add-ons"
echo "  Cluster: ${CLUSTER_NAME} | Region: ${REGION}"
echo "============================================================"

# ── 1. kube-proxy ─────────────────────────────────────────────────────────────
echo ""
echo "[1/5] Installing kube-proxy add-on..."
aws eks create-addon \
  --cluster-name "${CLUSTER_NAME}" \
  --addon-name kube-proxy \
  --resolve-conflicts OVERWRITE \
  --region "${REGION}" 2>/dev/null || \
aws eks update-addon \
  --cluster-name "${CLUSTER_NAME}" \
  --addon-name kube-proxy \
  --resolve-conflicts OVERWRITE \
  --region "${REGION}"
echo "[1/5] ✓ kube-proxy installed"

# ── 2. CoreDNS ────────────────────────────────────────────────────────────────
echo ""
echo "[2/5] Installing CoreDNS add-on..."
aws eks create-addon \
  --cluster-name "${CLUSTER_NAME}" \
  --addon-name coredns \
  --resolve-conflicts OVERWRITE \
  --region "${REGION}" 2>/dev/null || \
aws eks update-addon \
  --cluster-name "${CLUSTER_NAME}" \
  --addon-name coredns \
  --resolve-conflicts OVERWRITE \
  --region "${REGION}"
echo "[2/5] ✓ CoreDNS installed"

# ── 3. Amazon EBS CSI Driver ──────────────────────────────────────────────────
echo ""
echo "[3/5] Creating IRSA for EBS CSI driver..."

eksctl create iamserviceaccount \
  --cluster  "${CLUSTER_NAME}" \
  --region   "${REGION}" \
  --namespace kube-system \
  --name     ebs-csi-controller-sa \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --override-existing-serviceaccounts

echo "  Installing EBS CSI add-on..."
aws eks create-addon \
  --cluster-name "${CLUSTER_NAME}" \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn \
    "arn:aws:iam::${AWS_ACCOUNT_ID}:role/eksctl-${CLUSTER_NAME}-addon-iamserviceaccount-kube-system-ebs-csi-controller-sa" \
  --resolve-conflicts OVERWRITE \
  --region "${REGION}" 2>/dev/null || \
aws eks update-addon \
  --cluster-name "${CLUSTER_NAME}" \
  --addon-name aws-ebs-csi-driver \
  --resolve-conflicts OVERWRITE \
  --region "${REGION}"
echo "[3/5] ✓ EBS CSI driver installed"

# ── 4. Amazon EFS CSI Driver ──────────────────────────────────────────────────
echo ""
echo "[4/5] Creating IRSA for EFS CSI driver..."

# EFS CSI needs a custom policy (not AWS managed)
EFS_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AmazonEFSCSIDriverPolicy"

# Create the policy if it doesn't exist
aws iam create-policy \
  --policy-name AmazonEFSCSIDriverPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "ec2:DescribeAvailabilityZones"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "elasticfilesystem:CreateAccessPoint"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "aws:RequestTag/efs.csi.aws.com/cluster": "true"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": [
          "elasticfilesystem:TagResource"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "aws:ResourceTag/efs.csi.aws.com/cluster": "true"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": "elasticfilesystem:DeleteAccessPoint",
        "Resource": "*",
        "Condition": {
          "StringEquals": {
            "aws:ResourceTag/efs.csi.aws.com/cluster": "true"
          }
        }
      }
    ]
  }' \
  --region "${REGION}" 2>/dev/null || echo "  (policy already exists, skipping)"

eksctl create iamserviceaccount \
  --cluster  "${CLUSTER_NAME}" \
  --region   "${REGION}" \
  --namespace kube-system \
  --name     efs-csi-controller-sa \
  --attach-policy-arn "${EFS_POLICY_ARN}" \
  --approve \
  --override-existing-serviceaccounts

echo "  Installing EFS CSI add-on..."
aws eks create-addon \
  --cluster-name "${CLUSTER_NAME}" \
  --addon-name aws-efs-csi-driver \
  --service-account-role-arn \
    "arn:aws:iam::${AWS_ACCOUNT_ID}:role/eksctl-${CLUSTER_NAME}-addon-iamserviceaccount-kube-system-efs-csi-controller-sa" \
  --resolve-conflicts OVERWRITE \
  --region "${REGION}" 2>/dev/null || \
aws eks update-addon \
  --cluster-name "${CLUSTER_NAME}" \
  --addon-name aws-efs-csi-driver \
  --resolve-conflicts OVERWRITE \
  --region "${REGION}"
echo "[4/5] ✓ EFS CSI driver installed"

# ── 5. AWS Load Balancer Controller ──────────────────────────────────────────
echo ""
echo "[5/5] Installing AWS Load Balancer Controller..."

# 5a. Create IAM policy from local file
ALB_POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
ALB_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ALB_POLICY_NAME}"

aws iam create-policy \
  --policy-name "${ALB_POLICY_NAME}" \
  --policy-document "file://$(dirname "$0")/iam/alb-controller-policy.json" \
  --region "${REGION}" 2>/dev/null || echo "  (ALB policy already exists, skipping)"

# 5b. Create IRSA for the controller
eksctl create iamserviceaccount \
  --cluster    "${CLUSTER_NAME}" \
  --region     "${REGION}" \
  --namespace  kube-system \
  --name       aws-load-balancer-controller \
  --attach-policy-arn "${ALB_POLICY_ARN}" \
  --approve \
  --override-existing-serviceaccounts

# 5c. Install via Helm
if ! command -v helm &>/dev/null; then
  echo "  ERROR: helm not found. Install with: brew install helm"
  exit 1
fi

helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update eks

helm upgrade --install aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  --namespace kube-system \
  --version   "${ALB_CHART_VERSION}" \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region="${REGION}" \
  --set vpcId="$(aws eks describe-cluster \
    --name "${CLUSTER_NAME}" \
    --region "${REGION}" \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)" \
  --wait

echo "[5/5] ✓ AWS Load Balancer Controller installed"

# ── Wait for all add-ons to be ACTIVE ────────────────────────────────────────
echo ""
echo "  Waiting for all add-ons to reach ACTIVE state..."
for ADDON in kube-proxy coredns aws-ebs-csi-driver aws-efs-csi-driver; do
  echo -n "  Waiting for ${ADDON}... "
  aws eks wait addon-active \
    --cluster-name "${CLUSTER_NAME}" \
    --addon-name   "${ADDON}" \
    --region       "${REGION}"
  echo "✓"
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  ✓ All add-ons installed successfully"
echo ""
echo "  Add-ons:  kube-proxy, CoreDNS, EBS CSI, EFS CSI"
echo "  Helm:     aws-load-balancer-controller v${ALB_CHART_VERSION}"
echo ""
echo "  Next step:  ./infra/03-oidc-irsa.sh"
echo "============================================================"

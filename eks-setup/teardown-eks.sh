#!/usr/bin/env bash
# =============================================================================
# teardown-eks.sh — Delete all Kubernetes and EKS resources
#
# Deletes (in order):
#   1. K8s app namespace and EFS PVC
#   2. ALB Controller (Helm + CRDs)
#   3. EKS managed add-ons
#   4. Add-on IAM roles and policies
#   5. iamserviceaccount CloudFormation stacks (via eksctl)
#   6. App service IAM roles and policies
#   7. EKS cluster — node groups, OIDC, cluster service role, VPC (via eksctl)
#
# Notes:
#   - eksctl delete cluster handles its own CloudFormation stacks automatically
#   - eksctl-created roles (ServiceRole, NodeInstanceRole) are deleted with the stack
#   - Does NOT delete: DynamoDB, SQS, Aurora, EFS, S3, DAX, CloudFront, ECR
#
# Usage:
#   export AWS_ACCOUNT_ID=123456789012
#   ./eks-setup/teardown-eks.sh
# =============================================================================
set -euo pipefail
export AWS_PAGER=""

CLUSTER_NAME="demo-cluster"
REGION="ap-southeast-1"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"

echo "============================================================"
echo "  EKS Teardown: ${CLUSTER_NAME}"
echo "  Region:       ${REGION}"
echo "  Account:      ${AWS_ACCOUNT_ID}"
echo "============================================================"
echo ""
read -p "This will delete the EKS cluster and all related resources. Continue? (y/N) " CONFIRM
[[ "${CONFIRM}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── Step 1: K8s app resources ─────────────────────────────────────────────────
echo ""
echo "[1/7] Deleting K8s app resources..."
kubectl delete namespace app --ignore-not-found 2>/dev/null || true
kubectl delete -f eks-setup/k8s/provider-service/02-efs-pvc.yaml \
  --ignore-not-found 2>/dev/null || true
echo "[1/7] Done"

# ── Step 2: ALB Controller (Helm + CRDs) ─────────────────────────────────────
echo ""
echo "[2/7] Removing ALB Controller..."
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null \
  && echo "  ✓ Helm release deleted" || echo "  Helm release not found"
kubectl delete crd ingressclassparams.elbv2.k8s.aws 2>/dev/null || true
kubectl delete crd targetgroupbindings.elbv2.k8s.aws 2>/dev/null || true
echo "[2/7] Done"

# ── Step 3: EKS managed add-ons ──────────────────────────────────────────────
echo ""
echo "[3/7] Deleting EKS managed add-ons..."
for ADDON in aws-ebs-csi-driver aws-efs-csi-driver kube-proxy coredns; do
  aws eks delete-addon \
    --cluster-name "${CLUSTER_NAME}" \
    --addon-name   "${ADDON}" \
    --region       "${REGION}" 2>/dev/null \
    && echo "  ✓ ${ADDON}" || echo "  not found: ${ADDON}"
done
echo "[3/7] Done"

# ── Step 4: Add-on IAM roles and policies ────────────────────────────────────
echo ""
echo "[4/7] Deleting add-on IAM roles and policies..."

# EBS CSI
aws iam detach-role-policy --role-name eks-ebs-csi-driver-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy 2>/dev/null || true
aws iam delete-role --role-name eks-ebs-csi-driver-role 2>/dev/null \
  && echo "  ✓ eks-ebs-csi-driver-role" || echo "  not found: eks-ebs-csi-driver-role"

# EFS CSI
aws iam detach-role-policy --role-name eks-efs-csi-driver-role \
  --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AmazonEFSCSIDriverPolicy" 2>/dev/null || true
aws iam delete-role --role-name eks-efs-csi-driver-role 2>/dev/null \
  && echo "  ✓ eks-efs-csi-driver-role" || echo "  not found: eks-efs-csi-driver-role"

# ALB Controller
aws iam detach-role-policy --role-name eks-alb-controller-role \
  --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy" 2>/dev/null || true
aws iam delete-role --role-name eks-alb-controller-role 2>/dev/null \
  && echo "  ✓ eks-alb-controller-role" || echo "  not found: eks-alb-controller-role"

for POLICY in AmazonEFSCSIDriverPolicy AWSLoadBalancerControllerIAMPolicy; do
  aws iam delete-policy \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY}" 2>/dev/null \
    && echo "  ✓ policy: ${POLICY}" || echo "  not found: ${POLICY}"
done
echo "[4/7] Done"

# ── Step 5: iamserviceaccount stacks (via eksctl) ────────────────────────────
# eksctl delete iamserviceaccount deletes both the K8s SA and its CloudFormation
# stack. Before deleting, disable termination protection if enabled.
echo ""
echo "[5/7] Deleting iamserviceaccount stacks via eksctl..."

for SA in ebs-csi-controller-sa efs-csi-controller-sa aws-load-balancer-controller; do
  STACK_NAME="eksctl-${CLUSTER_NAME}-addon-iamserviceaccount-kube-system-${SA}"

  # Disable termination protection if enabled
  PROTECTION=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" --region "${REGION}" \
    --query 'Stacks[0].EnableTerminationProtection' \
    --output text 2>/dev/null || echo "False")

  if [[ "${PROTECTION}" == "True" ]]; then
    echo "  Disabling termination protection on ${STACK_NAME}..."
    aws cloudformation update-termination-protection \
      --stack-name "${STACK_NAME}" \
      --no-enable-termination-protection \
      --region "${REGION}"
  fi

  eksctl delete iamserviceaccount \
    --cluster   "${CLUSTER_NAME}" \
    --region    "${REGION}" \
    --namespace kube-system \
    --name      "${SA}" 2>/dev/null \
    && echo "  ✓ iamserviceaccount: ${SA}" || echo "  not found: ${SA}"
done
echo "[5/7] Done"

# ── Step 6: App service IAM roles and policies ────────────────────────────────
echo ""
echo "[6/7] Deleting app service IAM roles..."
for ROLE in eks-product-service-role eks-order-service-role; do
  POLICIES=$(aws iam list-attached-role-policies --role-name "${ROLE}" \
    --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || true)
  for POLICY_ARN in ${POLICIES}; do
    aws iam detach-role-policy --role-name "${ROLE}" --policy-arn "${POLICY_ARN}" 2>/dev/null || true
  done
  aws iam delete-role --role-name "${ROLE}" 2>/dev/null \
    && echo "  ✓ ${ROLE}" || echo "  not found: ${ROLE}"
done

for POLICY in ProductServicePolicy OrderServicePolicy; do
  aws iam delete-policy \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY}" 2>/dev/null \
    && echo "  ✓ policy: ${POLICY}" || echo "  not found: ${POLICY}"
done
echo "[6/7] Done"

# ── Step 7: EKS cluster (via eksctl) ──────────────────────────────────────────
# eksctl delete cluster:
#   - deletes node groups
#   - deletes cluster CloudFormation stack (including ServiceRole + NodeInstanceRole)
#   - deletes OIDC provider
#   - deletes VPC and all networking resources
echo ""
echo "[7/7] Deleting EKS cluster via eksctl: ${CLUSTER_NAME}..."
echo "  Duration: ~10 minutes"

# Disable termination protection on cluster stack if enabled
CLUSTER_STACK="eksctl-${CLUSTER_NAME}-cluster"
PROTECTION=$(aws cloudformation describe-stacks \
  --stack-name "${CLUSTER_STACK}" --region "${REGION}" \
  --query 'Stacks[0].EnableTerminationProtection' \
  --output text 2>/dev/null || echo "False")

if [[ "${PROTECTION}" == "True" ]]; then
  echo "  Disabling termination protection on ${CLUSTER_STACK}..."
  aws cloudformation update-termination-protection \
    --stack-name "${CLUSTER_STACK}" \
    --no-enable-termination-protection \
    --region "${REGION}"
fi

eksctl delete cluster --name "${CLUSTER_NAME}" --region "${REGION}"
echo "[7/7] Done"

echo ""
echo "============================================================"
echo "  EKS teardown complete"
echo ""
echo "  Remaining resources (not deleted by this script):"
echo "    DynamoDB, SQS, Aurora, DAX, EFS, S3, CloudFront, ECR"
echo "  See guides/teardown.md for full teardown."
echo "============================================================"

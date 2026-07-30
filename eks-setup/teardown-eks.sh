#!/usr/bin/env bash
# =============================================================================
# teardown-eks.sh — Delete all Kubernetes and EKS resources
#
# Deletes (in order):
#   1. K8s app namespace and EFS PVC
#   2. ALB Controller (Helm + CRDs)
#   3. EKS managed add-ons
#   4. Add-on IAM roles and policies
#   5. CloudFormation stacks created by eksctl iamserviceaccount
#   6. App service IAM roles and policies
#   7. EKS cluster (node groups + OIDC + VPC)
#
# Does NOT delete: DynamoDB, SQS, Aurora, EFS, S3, DAX, CloudFront, ECR
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
kubectl delete namespace app --ignore-not-found
kubectl delete -f eks-setup/k8s/provider-service/02-efs-pvc.yaml --ignore-not-found 2>/dev/null || true
echo "[1/7] Done"

# ── Step 2: ALB Controller ────────────────────────────────────────────────────
echo ""
echo "[2/7] Removing ALB Controller..."
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null \
  && echo "  Helm release deleted" || echo "  Helm release not found"

kubectl delete crd ingressclassparams.elbv2.k8s.aws 2>/dev/null || true
kubectl delete crd targetgroupbindings.elbv2.k8s.aws 2>/dev/null || true
echo "[2/7] Done"

# ── Step 3: EKS managed add-ons ──────────────────────────────────────────────
echo ""
echo "[3/7] Deleting EKS add-ons..."
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
echo "[4/7] Deleting add-on IAM roles..."

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

# Policies
for POLICY in AmazonEFSCSIDriverPolicy AWSLoadBalancerControllerIAMPolicy; do
  aws iam delete-policy \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY}" 2>/dev/null \
    && echo "  ✓ policy: ${POLICY}" || echo "  not found: ${POLICY}"
done
echo "[4/7] Done"

# ── Step 5: CloudFormation stacks (from eksctl iamserviceaccount) ─────────────
echo ""
echo "[5/7] Deleting eksctl CloudFormation stacks..."
STACKS=$(aws cloudformation list-stacks \
  --region "${REGION}" \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?starts_with(StackName,'eksctl-${CLUSTER_NAME}')].StackName" \
  --output text)

if [[ -z "${STACKS}" ]]; then
  echo "  No eksctl stacks found"
else
  for STACK in ${STACKS}; do
    aws cloudformation delete-stack --stack-name "${STACK}" --region "${REGION}"
    echo "  Deleting: ${STACK}"
  done

  echo "  Waiting for stacks to delete..."
  for STACK in ${STACKS}; do
    aws cloudformation wait stack-delete-complete \
      --stack-name "${STACK}" --region "${REGION}" 2>/dev/null || true
  done
fi
echo "[5/7] Done"

# ── Step 6: App service IAM roles and policies ────────────────────────────────
echo ""
echo "[6/7] Deleting app service IAM roles..."
for ROLE in eks-product-service-role eks-order-service-role; do
  POLICIES=$(aws iam list-attached-role-policies --role-name "${ROLE}" \
    --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || true)
  if [[ -n "${POLICIES}" ]]; then
    for POLICY_ARN in ${POLICIES}; do
      aws iam detach-role-policy --role-name "${ROLE}" --policy-arn "${POLICY_ARN}"
    done
  fi
  aws iam delete-role --role-name "${ROLE}" 2>/dev/null \
    && echo "  ✓ ${ROLE}" || echo "  not found: ${ROLE}"
done

for POLICY in ProductServicePolicy OrderServicePolicy; do
  aws iam delete-policy \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY}" 2>/dev/null \
    && echo "  ✓ policy: ${POLICY}" || echo "  not found: ${POLICY}"
done
echo "[6/7] Done"

# ── Step 7: EKS cluster ───────────────────────────────────────────────────────
echo ""
echo "[7/7] Deleting EKS cluster: ${CLUSTER_NAME}..."
echo "  This also deletes node groups, OIDC provider, and the VPC."
echo "  Duration: ~10 minutes"
eksctl delete cluster --name "${CLUSTER_NAME}" --region "${REGION}"
echo "[7/7] Done"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  EKS teardown complete"
echo ""
echo "  Remaining resources (not deleted by this script):"
echo "    DynamoDB, SQS, Aurora, DAX, EFS, S3, CloudFront, ECR"
echo "  See guides/teardown.md for full teardown including those."
echo "============================================================"

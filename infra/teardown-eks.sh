#!/usr/bin/env bash
# =============================================================================
# DELETE All AWS Resources that created manually before run this script
# Aurora, EFS, VPC Endpoints, S3 buckets, CloudFront, ECR repos, etc.
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

# ── Helper: wait for background jobs and report failures ─────────────────────
wait_all() {
  local failed=0
  for pid in "$@"; do
    wait "$pid" || { echo "  ⚠ background task $pid failed (non-fatal)"; failed=1; }
  done
  return $failed
}

# ── Step 1: Delete ALB and K8s app resources ─────────────────────────────────
echo ""
echo "[1/4] Removing ALB and K8s app resources..."

# a. Scale down all deployments — nothing can recreate the ALB
echo "  Scaling down deployments..."
kubectl scale deployment --all -n app --replicas=0 2>/dev/null || true

# b. Delete Ingress — signal the ALB controller, then immediately strip the
#    finalizer so kubectl does not block waiting for ALB deprovisioning.
#    The ALB itself is force-deleted via AWS CLI in the next step.
echo "  Deleting Ingress (no-wait)..."
kubectl delete ingress app-ingress -n app --ignore-not-found --wait=false 2>/dev/null || true
kubectl patch ingress app-ingress -n app \
  --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]' \
  2>/dev/null || true  # no-op if already gone

# Give the ALB controller a moment to register the deletion before we look up the ALB.
echo "  Waiting 15s for ALB controller to start deprovisioning..."
sleep 15

# c. Delete ALB directly via AWS CLI — find all ALBs in the EKS VPC
echo "  Looking up ALBs in cluster VPC..."
EKS_VPC_ID=$(aws eks describe-cluster \
  --name "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text 2>/dev/null || true)
echo "  EKS VPC: ${EKS_VPC_ID}"

if [[ -n "${EKS_VPC_ID}" && "${EKS_VPC_ID}" != "None" ]]; then
  ALB_ARNS=$(aws elbv2 describe-load-balancers \
    --region "${REGION}" \
    --query "LoadBalancers[?VpcId=='${EKS_VPC_ID}'].LoadBalancerArn" \
    --output text 2>/dev/null || true)

  if [[ -n "${ALB_ARNS}" ]]; then
    for ARN in ${ALB_ARNS}; do
      echo "  Found ALB: ${ARN}"

      # Collect target groups while ALB still exists
      TG_ARNS=$(aws elbv2 describe-target-groups \
        --load-balancer-arn "${ARN}" \
        --region "${REGION}" \
        --query 'TargetGroups[*].TargetGroupArn' \
        --output text 2>/dev/null || true)

      # Delete the ALB
      aws elbv2 delete-load-balancer \
        --load-balancer-arn "${ARN}" \
        --region "${REGION}" \
        && echo "  ✓ ALB delete initiated" || echo "  ⚠ could not delete ALB"

      # Wait for ALB to be fully gone before deleting target groups (max 3 min)
      echo "  Waiting for ALB deletion (up to 3 min)..."
      timeout 180 aws elbv2 wait load-balancers-deleted \
        --load-balancer-arns "${ARN}" \
        --region "${REGION}" 2>/dev/null || {
        echo "  ⚠ ALB wait timed out — continuing anyway (target groups may need manual cleanup)"
      }
      echo "  ✓ ALB deletion confirmed (or timed out)"

      # Delete target groups
      for TG_ARN in ${TG_ARNS}; do
        aws elbv2 delete-target-group \
          --target-group-arn "${TG_ARN}" \
          --region "${REGION}" 2>/dev/null \
          && echo "  ✓ target group deleted: ${TG_ARN##*/}" || true
      done
    done
  else
    echo "  ✓ No ALBs found in VPC"
  fi
fi

# d. Delete the namespace (remaining K8s objects)
echo "  Deleting namespace app..."
kubectl delete namespace app --ignore-not-found --wait=false 2>/dev/null || true

echo "[1/4] Done"

# ── Step 2: EKS add-ons (parallel) ───────────────────────────────────────────
# Helm uninstall is skipped — the cluster is being deleted anyway.
# ALB deprovisioning was already triggered in step 1 via namespace deletion.
echo ""
echo "[2/4] Deleting EKS add-ons in parallel..."

for ADDON in aws-ebs-csi-driver aws-efs-csi-driver kube-proxy coredns; do
  (
    aws eks delete-addon \
      --cluster-name "${CLUSTER_NAME}" \
      --addon-name   "${ADDON}" \
      --region       "${REGION}" \
      --no-preserve 2>/dev/null \
      && echo "  ✓ add-on delete initiated: ${ADDON}" \
      || echo "  not found: ${ADDON}"
  ) &
done
wait
echo "[2/4] Done"

# ── Step 3: IAM roles and policies (parallel) ─────────────────────────────────
echo ""
echo "[3/4] Deleting IAM roles and policies in parallel..."

# Add-on IAM roles
(
  # EBS CSI
  aws iam detach-role-policy --role-name eks-ebs-csi-driver-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy 2>/dev/null || true
  aws iam delete-role --role-name eks-ebs-csi-driver-role 2>/dev/null \
    && echo "  ✓ eks-ebs-csi-driver-role" || echo "  not found: eks-ebs-csi-driver-role"
) &
PID_EBS_ROLE=$!

(
  # EFS CSI
  aws iam detach-role-policy --role-name eks-efs-csi-driver-role \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AmazonEFSCSIDriverPolicy" 2>/dev/null || true
  aws iam delete-role --role-name eks-efs-csi-driver-role 2>/dev/null \
    && echo "  ✓ eks-efs-csi-driver-role" || echo "  not found: eks-efs-csi-driver-role"
  aws iam delete-policy \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AmazonEFSCSIDriverPolicy" 2>/dev/null \
    && echo "  ✓ policy: AmazonEFSCSIDriverPolicy" || echo "  not found: AmazonEFSCSIDriverPolicy"
) &
PID_EFS_ROLE=$!

(
  # ALB Controller
  aws iam detach-role-policy --role-name eks-alb-controller-role \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy" 2>/dev/null || true
  aws iam delete-role --role-name eks-alb-controller-role 2>/dev/null \
    && echo "  ✓ eks-alb-controller-role" || echo "  not found: eks-alb-controller-role"
  aws iam delete-policy \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy" 2>/dev/null \
    && echo "  ✓ policy: AWSLoadBalancerControllerIAMPolicy" || echo "  not found: AWSLoadBalancerControllerIAMPolicy"
) &
PID_ALB_ROLE=$!

# App service IAM roles
(
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
) &
PID_APP_ROLES=$!

wait_all $PID_EBS_ROLE $PID_EFS_ROLE $PID_ALB_ROLE $PID_APP_ROLES || true
echo "[3/4] Done"

# ── Step 4: EKS cluster via eksctl ────────────────────────────────────────────
# Deletes: node groups, cluster CF stack (ServiceRole + NodeInstanceRole),
#          iamserviceaccount stacks, OIDC provider, VPC and all networking.
# Duration: ~10 minutes
echo ""
echo "[4/4] Deleting EKS cluster: ${CLUSTER_NAME} (~10 min)..."

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
echo "[4/4] Done"

echo ""
echo "============================================================"
echo "  EKS teardown complete"
echo ""
echo "  Remaining resources (not deleted by this script):"
echo "    DynamoDB, SQS, Aurora, DAX, EFS, S3, CloudFront, ECR"
echo "  See guides/teardown.md for full teardown."
echo "============================================================"

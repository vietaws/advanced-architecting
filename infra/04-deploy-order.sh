#!/usr/bin/env bash
# =============================================================================
# 04-deploy-order.sh — Deploy order-service to EKS
#
# Applies: Secret, ServiceAccount, Deployment, Service
#
# Prerequisites:
#   - Namespace 'app' exists (run 04-k8s-setup.sh once first, or kubectl apply -f infra/k8s/01-namespace.yaml)
#   - infra/k8s/order-service/01-secret.yaml filled in
#   - Image pushed to registry (see infra/IMAGES.md)
#
# Required env vars:
#   AWS_ACCOUNT_ID  — AWS account number
#
# Usage:
#   export AWS_ACCOUNT_ID=123456789012
#   ./infra/04-deploy-order.sh
# =============================================================================
set -euo pipefail
export AWS_PAGER=""

CLUSTER_NAME="demo-cluster"
REGION="ap-southeast-1"
NAMESPACE="app"
SVC="order-service"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/k8s"

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"

aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}"

echo "============================================================"
echo "  Deploying: ${SVC}"
echo "  Cluster:   ${CLUSTER_NAME} / namespace: ${NAMESPACE}"
echo "============================================================"

# Patch role ARN and image URI placeholders
sed -i.bak \
  "s|arn:aws:iam::AWS_ACCOUNT_ID:|arn:aws:iam::${AWS_ACCOUNT_ID}:|g" \
  "${K8S_DIR}/${SVC}/03-serviceaccount.yaml"
sed -i.bak \
  "s|AWS_ACCOUNT_ID\.dkr\.ecr|${AWS_ACCOUNT_ID}.dkr.ecr|g" \
  "${K8S_DIR}/${SVC}/05-deployment.yaml"
find "${K8S_DIR}/${SVC}" -name "*.bak" -delete

# Apply all manifests for this service
kubectl apply -f "${K8S_DIR}/${SVC}/"

# Wait for rollout
echo ""
echo "  Waiting for rollout..."
kubectl rollout status deployment/"${SVC}" \
  --namespace "${NAMESPACE}" --timeout=120s

echo ""
echo "  ${SVC} deployed successfully"
kubectl get pods -n "${NAMESPACE}" -l app="${SVC}"

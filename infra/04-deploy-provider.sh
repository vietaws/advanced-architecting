#!/usr/bin/env bash
# =============================================================================
# 04-deploy-provider.sh — Deploy provider-service to EKS
#
# Applies: EFS PVC, Secret, ServiceAccount, Deployment, Service
#
# Prerequisites:
#   - Namespace 'app' exists (run 04-k8s-setup.sh once first, or kubectl apply -f infra/k8s/01-namespace.yaml)
#   - infra/k8s/provider-service/01-secret.yaml filled in
#   - EFS file system and mount targets exist (Phase 0 Step 6)
#   - Image pushed to registry (see infra/IMAGES.md)
#
# Required env vars:
#   AWS_ACCOUNT_ID     — AWS account number
#   EFS_FILE_SYSTEM_ID — EFS filesystem ID (e.g. fs-0123456789abcdef0)
#
# Usage:
#   export AWS_ACCOUNT_ID=123456789012
#   export EFS_FILE_SYSTEM_ID=fs-0123456789abcdef0
#   ./infra/04-deploy-provider.sh
# =============================================================================
set -euo pipefail
export AWS_PAGER=""

CLUSTER_NAME="demo-cluster"
REGION="ap-southeast-1"
NAMESPACE="app"
SVC="provider-service"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/k8s"

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
EFS_FILE_SYSTEM_ID="${EFS_FILE_SYSTEM_ID:?'Set EFS_FILE_SYSTEM_ID env var'}"

aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}"

echo "============================================================"
echo "  Deploying: ${SVC}"
echo "  Cluster:   ${CLUSTER_NAME} / namespace: ${NAMESPACE}"
echo "============================================================"

# Apply EFS PVC (substitute real filesystem ID)
EFS_PVC_TMP="$(mktemp).yaml"
sed "s|EFS_FILE_SYSTEM_ID|${EFS_FILE_SYSTEM_ID}|g" \
  "${K8S_DIR}/${SVC}/02-efs-pvc.yaml" > "${EFS_PVC_TMP}"
kubectl apply -f "${EFS_PVC_TMP}"
rm -f "${EFS_PVC_TMP}"
echo "  EFS PVC applied"

# Patch image URI placeholder
sed -i.bak \
  "s|AWS_ACCOUNT_ID\.dkr\.ecr|${AWS_ACCOUNT_ID}.dkr.ecr|g" \
  "${K8S_DIR}/${SVC}/05-deployment.yaml"
find "${K8S_DIR}/${SVC}" -name "*.bak" -delete

# Apply all manifests for this service (excludes 02-efs-pvc.yaml — already applied above)
kubectl apply -f "${K8S_DIR}/${SVC}/01-secret.yaml"
kubectl apply -f "${K8S_DIR}/${SVC}/03-serviceaccount.yaml"
kubectl apply -f "${K8S_DIR}/${SVC}/04-service.yaml"
kubectl apply -f "${K8S_DIR}/${SVC}/05-deployment.yaml"

# Wait for rollout
echo ""
echo "  Waiting for rollout..."
kubectl rollout status deployment/"${SVC}" \
  --namespace "${NAMESPACE}" --timeout=120s

echo ""
echo "  ${SVC} deployed successfully"
kubectl get pods -n "${NAMESPACE}" -l app="${SVC}"

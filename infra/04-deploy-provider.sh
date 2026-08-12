#!/usr/bin/env bash
# =============================================================================
# 04-deploy-provider.sh — Deploy provider-service to EKS
#
# All service-specific variables are managed here.
# The YAML files under infra/k8s/provider-service/ use placeholders and are
# never modified directly — values are injected at deploy time via temp files.
#
# AWS Resources required for provider-service:
#   1. EFS File System
#   2. Aurora RDS Cluster
# =============================================================================
set -euo pipefail
export AWS_PAGER=""

# ── Cluster ───────────────────────────────────────────────────────────────────
CLUSTER_NAME="demo-cluster"
REGION="ap-southeast-1"
NAMESPACE="app"
SVC="provider-service"

# ── Service variables (edit here) ─────────────────────────────────────────────
EFS_FILE_SYSTEM_ID="EFS_FILE_SYSTEM_ID_PLACEHOLDER" # e.g. fs-12345678
RDS_HOST="RDS_HOST_PLACEHOLDER" # e.g. mydb.cluster-123456789012.ap-southeast-1.rds.amazonaws.com
RDS_PORT="5432"
RDS_DATABASE="providers_db"
RDS_USER="dbadmin"
RDS_PASSWORD="DemoPassword"

# ── Derived ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/k8s"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"

aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}"

echo "============================================================"
echo "  Deploying: ${SVC}"
echo "  Cluster:   ${CLUSTER_NAME} / namespace: ${NAMESPACE}"
echo "============================================================"

# ── EFS PVC (inject filesystem ID via temp file) ───────────────────────────────
EFS_PVC_TMP="$(mktemp).yaml"
sed \
  "s|EFS_FILE_SYSTEM_ID|${EFS_FILE_SYSTEM_ID}|g" \
  "${K8S_DIR}/${SVC}/02-efs-pvc.yaml" > "${EFS_PVC_TMP}"
kubectl apply -f "${EFS_PVC_TMP}"
rm -f "${EFS_PVC_TMP}"
echo "  EFS PVC applied"

# ── Secret (inject variables via temp file — YAML stays pristine) ─────────────
SECRET_TMP="$(mktemp).yaml"
sed \
  -e "s|REPLACE_RDS_HOST|${RDS_HOST}|g" \
  -e "s|REPLACE_RDS_USER|${RDS_USER}|g" \
  -e "s|REPLACE_RDS_PASSWORD|${RDS_PASSWORD}|g" \
  "${K8S_DIR}/${SVC}/01-secret.yaml" > "${SECRET_TMP}"
kubectl apply -f "${SECRET_TMP}"
rm -f "${SECRET_TMP}"
echo "  Secret applied"

# ── ServiceAccount ─────────────────────────────────────────────────────────────
kubectl apply -f "${K8S_DIR}/${SVC}/03-serviceaccount.yaml"
echo "  ServiceAccount applied"

# ── Deployment (patch ECR account ID) ─────────────────────────────────────────
DEPLOY_TMP="$(mktemp).yaml"
sed \
  "s|AWS_ACCOUNT_ID\.dkr\.ecr|${AWS_ACCOUNT_ID}.dkr.ecr|g" \
  "${K8S_DIR}/${SVC}/05-deployment.yaml" > "${DEPLOY_TMP}"
kubectl apply -f "${DEPLOY_TMP}"
rm -f "${DEPLOY_TMP}"
echo "  Deployment applied"

# ── Service ────────────────────────────────────────────────────────────────────
kubectl apply -f "${K8S_DIR}/${SVC}/04-service.yaml"
echo "  Service applied"

# ── Rollout ────────────────────────────────────────────────────────────────────
echo ""
echo "  Waiting for rollout..."
kubectl rollout status deployment/"${SVC}" \
  --namespace "${NAMESPACE}" --timeout=120s

echo ""
echo "  ${SVC} deployed successfully"
kubectl get pods -n "${NAMESPACE}" -l app="${SVC}"

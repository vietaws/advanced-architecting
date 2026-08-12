#!/usr/bin/env bash
# =============================================================================
#
# All service-specific variables are managed here.
# The YAML files under infra/k8s/product-service/ use placeholders and are
# never modified directly — values are injected at deploy time via temp files.
#
#
# AWS Resources required for product-service: 
#   1. S3 Product Bucket
#   2. Product DynamoDB Table
#   3. DAX Cluster
#   
# =============================================================================
set -euo pipefail
export AWS_PAGER=""

# ── Cluster ───────────────────────────────────────────────────────────────────
CLUSTER_NAME="demo-cluster"
REGION="ap-southeast-1"
NAMESPACE="app"
SVC="product-service"

# ── Service variables (edit here) ─────────────────────────────────────────────
DAX_ENDPOINT="daxs://dax-demo.kqensy.dax-clusters.ap-southeast-1.amazonaws.com"
S3_BUCKET="demo-product-images-d4b776b9"

# ── Derived ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/k8s"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"

aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}"

echo "============================================================"
echo "  Deploying: ${SVC}"
echo "  Cluster:   ${CLUSTER_NAME} / namespace: ${NAMESPACE}"
echo "============================================================"

# ── Secret (inject variables via temp file — YAML stays pristine) ─────────────
SECRET_TMP="$(mktemp).yaml"
sed \
  -e "s|REPLACE_DAX_ENDPOINT|${DAX_ENDPOINT}|g" \
  -e "s|REPLACE_S3_BUCKET|${S3_BUCKET}|g" \
  "${K8S_DIR}/${SVC}/01-secret.yaml" > "${SECRET_TMP}"
kubectl apply -f "${SECRET_TMP}"
rm -f "${SECRET_TMP}"
echo "  Secret applied"

# ── ServiceAccount (patch role ARN) ───────────────────────────────────────────
SA_TMP="$(mktemp).yaml"
sed \
  "s|arn:aws:iam::AWS_ACCOUNT_ID:|arn:aws:iam::${AWS_ACCOUNT_ID}:|g" \
  "${K8S_DIR}/${SVC}/03-serviceaccount.yaml" > "${SA_TMP}"
kubectl apply -f "${SA_TMP}"
rm -f "${SA_TMP}"
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

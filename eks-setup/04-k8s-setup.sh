#!/usr/bin/env bash
# =============================================================================
# 04-k8s-setup.sh — Deploy all Kubernetes resources to EKS
#
# Run AFTER: 03-oidc-irsa.sh
#
# Prerequisites:
#   Fill in real values in each service secret YAML before running:
#     eks-setup/k8s/product-service/product-service-secret.yaml
#     eks-setup/k8s/provider-service/provider-service-secret.yaml
#     eks-setup/k8s/order-service/order-service-secret.yaml
#
# Required env vars:
#   AWS_ACCOUNT_ID       — AWS account number
#   EFS_FILE_SYSTEM_ID   — EFS filesystem ID (e.g. fs-0123456789abcdef0)
#
# Usage:
#   export AWS_ACCOUNT_ID=123456789012
#   export EFS_FILE_SYSTEM_ID=fs-0123456789abcdef0
#   ./eks-setup/04-k8s-setup.sh
# =============================================================================
set -euo pipefail

CLUSTER_NAME="demo-cluster"
REGION="ap-southeast-1"
NAMESPACE="app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/k8s"

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
EFS_FILE_SYSTEM_ID="${EFS_FILE_SYSTEM_ID:?'Set EFS_FILE_SYSTEM_ID env var'}"

aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}"

echo "============================================================"
echo "  Deploying to EKS: ${CLUSTER_NAME} / namespace: ${NAMESPACE}"
echo "============================================================"

# ── Step 1: Namespace ─────────────────────────────────────────────────────────
echo ""
echo "[1/4] Namespace..."
kubectl apply -f "${K8S_DIR}/01-namespace.yaml"
echo "[1/4] ✓ Namespace '${NAMESPACE}' ready"

# ── Step 2: Patch service accounts and deployment images ─────────────────────
echo ""
echo "[2/4] Patching ServiceAccount role ARNs and image URIs..."

for SA_FILE in \
  "${K8S_DIR}/product-service/03-serviceaccount.yaml" \
  "${K8S_DIR}/order-service/03-serviceaccount.yaml"; do
  sed -i.bak \
    "s|arn:aws:iam::AWS_ACCOUNT_ID:|arn:aws:iam::${AWS_ACCOUNT_ID}:|g" \
    "${SA_FILE}"
done

for SVC in product-service provider-service order-service; do
  sed -i.bak \
    "s|AWS_ACCOUNT_ID\.dkr\.ecr|${AWS_ACCOUNT_ID}.dkr.ecr|g" \
    "${K8S_DIR}/${SVC}/05-deployment.yaml"
done

find "${K8S_DIR}" -name "*.bak" -delete
echo "[2/4] ✓ Patched"

# ── Step 3: EFS PVC ───────────────────────────────────────────────────────────
echo ""
echo "[3/4] EFS StorageClass + PV + PVC..."

EFS_PVC_TMP="$(mktemp).yaml"
sed "s|EFS_FILE_SYSTEM_ID|${EFS_FILE_SYSTEM_ID}|g" \
  "${K8S_DIR}/02-efs-pvc.yaml" > "${EFS_PVC_TMP}"
kubectl apply -f "${EFS_PVC_TMP}"
rm -f "${EFS_PVC_TMP}"

echo "[3/4] ✓ EFS PVC 'efs-claim' created"

# ── Step 4: All manifests (Secrets, ServiceAccounts, Deployments, Services, Ingress)
echo ""
echo "[4/4] Applying manifests..."

# Each service folder contains: Secret, ServiceAccount, Deployment, Service
for SVC in product-service provider-service order-service; do
  kubectl apply -f "${K8S_DIR}/${SVC}/"
done

kubectl apply -f "${K8S_DIR}/06-ingress.yaml"

echo "[4/4] ✓ All manifests applied"

# ── Wait for rollout ──────────────────────────────────────────────────────────
echo ""
echo "  Waiting for rollout..."
for SVC in product-service provider-service order-service; do
  kubectl rollout status deployment/"${SVC}" \
    --namespace "${NAMESPACE}" --timeout=120s
done

echo ""
echo "============================================================"
echo "  ✓ Deployment complete"
echo ""
kubectl get pods -n "${NAMESPACE}" -o wide
echo ""
kubectl get ingress -n "${NAMESPACE}"
echo "============================================================"

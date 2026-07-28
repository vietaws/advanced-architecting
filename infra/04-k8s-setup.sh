#!/usr/bin/env bash
# =============================================================================
# 04-k8s-setup.sh — Namespace, EFS PVC, K8s Secrets, and deploy all services
#
# Run AFTER: 03-oidc-irsa.sh
#
# What this does:
#   1. Creates namespace: app
#   2. Patches service account YAMLs with correct role ARNs
#   3. Creates EFS PersistentVolume + PVC
#   4. Creates K8s Secrets for all services
#   5. Applies all k8s manifests
#
# Required env vars:
#   AWS_ACCOUNT_ID          — AWS account number
#   EFS_FILE_SYSTEM_ID      — EFS filesystem ID (e.g. fs-0123456789abcdef0)
#   DAX_ENDPOINT            — DAX cluster endpoint
#   S3_BUCKET               — S3 bucket name for product images
#   RDS_HOST                — Aurora PostgreSQL endpoint
#   RDS_PASSWORD            — Aurora master password
#   SQS_QUEUE_URL           — Full SQS queue URL
#
# Usage:
#   chmod +x infra/04-k8s-setup.sh
#   export AWS_ACCOUNT_ID=123456789012
#   export EFS_FILE_SYSTEM_ID=fs-0123456789abcdef0
#   export DAX_ENDPOINT=daxs://...
#   export S3_BUCKET=demo-product-images-xxxx
#   export RDS_HOST=demo-aurora-cluster.cluster-xxx.ap-southeast-1.rds.amazonaws.com
#   export RDS_PASSWORD=YourSecurePassword
#   export SQS_QUEUE_URL=https://sqs.ap-southeast-1.amazonaws.com/123456789012/orders
#   ./infra/04-k8s-setup.sh
# =============================================================================
set -euo pipefail

# ── Variables ─────────────────────────────────────────────────────────────────
CLUSTER_NAME="demo-cluster"
REGION="ap-southeast-1"
NAMESPACE="app"
REPO_ROOT="$(dirname "$0")/.."

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
EFS_FILE_SYSTEM_ID="${EFS_FILE_SYSTEM_ID:?'Set EFS_FILE_SYSTEM_ID env var'}"
DAX_ENDPOINT="${DAX_ENDPOINT:?'Set DAX_ENDPOINT env var'}"
S3_BUCKET="${S3_BUCKET:?'Set S3_BUCKET env var'}"
RDS_HOST="${RDS_HOST:?'Set RDS_HOST env var'}"
RDS_PASSWORD="${RDS_PASSWORD:?'Set RDS_PASSWORD env var'}"
SQS_QUEUE_URL="${SQS_QUEUE_URL:?'Set SQS_QUEUE_URL env var'}"

# Stable defaults
RDS_PORT="${RDS_PORT:-5432}"
RDS_DATABASE="${RDS_DATABASE:-providers_db}"
RDS_USER="${RDS_USER:-dbadmin}"

# Ensure kubeconfig is pointing at the right cluster
aws eks update-kubeconfig \
  --name "${CLUSTER_NAME}" \
  --region "${REGION}"

echo "============================================================"
echo "  Deploying to EKS cluster: ${CLUSTER_NAME}"
echo "  Namespace: ${NAMESPACE}"
echo "============================================================"

# ── Step 1: Namespace ─────────────────────────────────────────────────────────
echo ""
echo "[1/5] Creating namespace..."
kubectl apply -f "${REPO_ROOT}/k8s/01-namespace.yaml"
echo "[1/5] ✓ Namespace '${NAMESPACE}' ready"

# ── Step 2: Patch service account YAMLs with correct role ARNs ───────────────
echo ""
echo "[2/5] Patching ServiceAccount role ARNs..."

# product-service-sa
sed -i.bak \
  "s|arn:aws:iam::AWS_ACCOUNT_ID:role/eks-product-service-role|arn:aws:iam::${AWS_ACCOUNT_ID}:role/eks-product-service-role|g" \
  "${REPO_ROOT}/k8s/product-service/03-serviceaccount.yaml"

# order-service-sa
sed -i.bak \
  "s|arn:aws:iam::AWS_ACCOUNT_ID:role/eks-order-service-role|arn:aws:iam::${AWS_ACCOUNT_ID}:role/eks-order-service-role|g" \
  "${REPO_ROOT}/k8s/order-service/03-serviceaccount.yaml"

# Patch deployment images to use correct account ID
for SVC in product-service provider-service order-service; do
  sed -i.bak \
    "s|AWS_ACCOUNT_ID\.dkr\.ecr|${AWS_ACCOUNT_ID}.dkr.ecr|g" \
    "${REPO_ROOT}/k8s/${SVC}/05-deployment.yaml"
done

# Clean up .bak files
find "${REPO_ROOT}/k8s" -name "*.bak" -delete

echo "[2/5] ✓ ServiceAccount ARNs and image URIs patched"

# ── Step 3: EFS StorageClass + PersistentVolume + PVC ─────────────────────────
echo ""
echo "[3/5] Creating EFS StorageClass + PV + PVC..."

# Render efs-pvc.yaml with real filesystem ID
EFS_PVC_RENDERED="$(mktemp).yaml"
sed "s|EFS_FILE_SYSTEM_ID|${EFS_FILE_SYSTEM_ID}|g" \
  "${REPO_ROOT}/k8s/02-efs-pvc.yaml" > "${EFS_PVC_RENDERED}"

kubectl apply -f "${EFS_PVC_RENDERED}"
rm -f "${EFS_PVC_RENDERED}"

echo "[3/5] ✓ EFS PVC 'efs-claim' created"

# ── Step 4: K8s Secrets ───────────────────────────────────────────────────────
echo ""
echo "[4/5] Creating K8s Secrets..."

# product-service-secret
kubectl create secret generic product-service-secret \
  --namespace "${NAMESPACE}" \
  --from-literal=AWS_REGION="${REGION}" \
  --from-literal=DYNAMODB_PRODUCTS_TABLE=products_table \
  --from-literal=DAX_ENDPOINT="${DAX_ENDPOINT}" \
  --from-literal=S3_BUCKET="${S3_BUCKET}" \
  --save-config \
  --dry-run=client -o yaml | kubectl apply -f -

# provider-service-secret
kubectl create secret generic provider-service-secret \
  --namespace "${NAMESPACE}" \
  --from-literal=AWS_REGION="${REGION}" \
  --from-literal=RDS_HOST="${RDS_HOST}" \
  --from-literal=RDS_PORT="${RDS_PORT}" \
  --from-literal=RDS_DATABASE="${RDS_DATABASE}" \
  --from-literal=RDS_USER="${RDS_USER}" \
  --from-literal=RDS_PASSWORD="${RDS_PASSWORD}" \
  --save-config \
  --dry-run=client -o yaml | kubectl apply -f -

# order-service-secret
kubectl create secret generic order-service-secret \
  --namespace "${NAMESPACE}" \
  --from-literal=AWS_REGION="${REGION}" \
  --from-literal=DYNAMODB_ORDERS_TABLE=orders_table \
  --from-literal=SQS_QUEUE_URL="${SQS_QUEUE_URL}" \
  --save-config \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[4/5] ✓ K8s Secrets created:"
echo "    product-service-secret"
echo "    provider-service-secret"
echo "    order-service-secret"

# ── Step 5: Apply all K8s manifests ──────────────────────────────────────────
echo ""
echo "[5/5] Applying Kubernetes manifests..."

# ServiceAccounts first (IRSA annotations must exist before pods start)
kubectl apply -f "${REPO_ROOT}/k8s/product-service/03-serviceaccount.yaml"
kubectl apply -f "${REPO_ROOT}/k8s/provider-service/03-serviceaccount.yaml"
kubectl apply -f "${REPO_ROOT}/k8s/order-service/03-serviceaccount.yaml"

# Services, Deployments, HPAs
for SVC in product-service provider-service order-service; do
  echo "  Applying ${SVC}..."
  kubectl apply -f "${REPO_ROOT}/k8s/${SVC}/"
done

# Ingress (ALB)
kubectl apply -f "${REPO_ROOT}/k8s/06-ingress.yaml"

echo "[5/5] ✓ All manifests applied"

# ── Verification ──────────────────────────────────────────────────────────────
echo ""
echo "  Waiting for rollout to complete..."
for SVC in product-service provider-service order-service; do
  echo -n "  Waiting for ${SVC}... "
  kubectl rollout status deployment/"${SVC}" \
    --namespace "${NAMESPACE}" \
    --timeout=120s
done

echo ""
echo "============================================================"
echo "  ✓ Deployment complete"
echo ""
kubectl get pods -n "${NAMESPACE}" -o wide
echo ""
kubectl get ingress -n "${NAMESPACE}"
echo ""
echo "  Next step:  ./infra/05-ecr.sh  (push images FIRST, then re-run this script)"
echo "============================================================"

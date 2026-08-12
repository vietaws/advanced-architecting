#!/usr/bin/env bash
set -euo pipefail

export AWS_PAGER=""

# ── Variables ─────────────────────────────────────────────────────────────────
CLUSTER_NAME="demo-cluster"
REGION="ap-southeast-1"
NAMESPACE="app"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"

# S3 bucket name for product images — must be set
PRODUCT_IMAGES_BUCKET="product-images-274595021951-ap-southeast-1-an"

INFRA_DIR="$(dirname "$0")"

echo "============================================================"
echo "  Setting up IRSA for microservices"
echo "  Cluster:   ${CLUSTER_NAME}"
echo "  Namespace: ${NAMESPACE}"
echo "  Account:   ${AWS_ACCOUNT_ID}"
echo "  S3 Bucket: ${PRODUCT_IMAGES_BUCKET}"
echo "============================================================"

# ── Resolve OIDC provider ID ──────────────────────────────────────────────────
OIDC_ID=$(aws eks describe-cluster \
  --name "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --query "cluster.identity.oidc.issuer" \
  --output text | sed 's|.*/||')

OIDC_PROVIDER="oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}"

echo ""
echo "  OIDC ID:       ${OIDC_ID}"
echo "  OIDC Provider: ${OIDC_PROVIDER}"

# ── Helper: build trust policy document ──────────────────────────────────────
trust_policy() {
  local SA_NAME="$1"
  cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:${SA_NAME}",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF
}

# ── Helper: create or update IAM role ────────────────────────────────────────
create_or_update_role() {
  local ROLE_NAME="$1"
  local SA_NAME="$2"
  local TRUST_DOC
  TRUST_DOC="$(trust_policy "${SA_NAME}")"

  if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
    echo "  Role ${ROLE_NAME} already exists — updating trust policy"
    aws iam update-assume-role-policy \
      --role-name "${ROLE_NAME}" \
      --policy-document "${TRUST_DOC}"
  else
    aws iam create-role \
      --role-name "${ROLE_NAME}" \
      --assume-role-policy-document "${TRUST_DOC}" \
      --tags "Key=project,Value=architecting-pro" "Key=cluster,Value=${CLUSTER_NAME}" \
      --output table
  fi
}

# =============================================================================
# product-service
# =============================================================================
echo ""
echo "── product-service ──────────────────────────────────────────"

# 1. Render policy: substitute placeholders
PRODUCT_POLICY_FILE="$(mktemp)"
sed \
  -e "s|AWS_ACCOUNT_ID|${AWS_ACCOUNT_ID}|g" \
  -e "s|PRODUCT_IMAGES_BUCKET|${PRODUCT_IMAGES_BUCKET}|g" \
  "${INFRA_DIR}/iam/product-service-policy.json" > "${PRODUCT_POLICY_FILE}"

# 2. Create / update the IAM policy
PRODUCT_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ProductServicePolicy"
if aws iam get-policy --policy-arn "${PRODUCT_POLICY_ARN}" &>/dev/null; then
  echo "  ProductServicePolicy already exists — creating new version"
  aws iam create-policy-version \
    --policy-arn "${PRODUCT_POLICY_ARN}" \
    --policy-document "file://${PRODUCT_POLICY_FILE}" \
    --set-as-default
else
  aws iam create-policy \
    --policy-name ProductServicePolicy \
    --policy-document "file://${PRODUCT_POLICY_FILE}" \
    --tags "Key=project,Value=architecting-pro"
fi

# 3. Create IAM role with OIDC trust
create_or_update_role "eks-product-service-role" "product-service-sa"

# 4. Attach policy to role
aws iam attach-role-policy \
  --role-name    eks-product-service-role \
  --policy-arn   "${PRODUCT_POLICY_ARN}" 2>/dev/null || true

echo "  ✓ eks-product-service-role created and policy attached"
echo "    Role ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/eks-product-service-role"
rm -f "${PRODUCT_POLICY_FILE}"

# =============================================================================
# order-service
# =============================================================================
echo ""
echo "── order-service ────────────────────────────────────────────"

# 1. Render policy: substitute placeholders
ORDER_POLICY_FILE="$(mktemp)"
sed \
  -e "s|AWS_ACCOUNT_ID|${AWS_ACCOUNT_ID}|g" \
  "${INFRA_DIR}/iam/order-service-policy.json" > "${ORDER_POLICY_FILE}"

# 2. Create / update the IAM policy
ORDER_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/OrderServicePolicy"
if aws iam get-policy --policy-arn "${ORDER_POLICY_ARN}" &>/dev/null; then
  echo "  OrderServicePolicy already exists — creating new version"
  aws iam create-policy-version \
    --policy-arn "${ORDER_POLICY_ARN}" \
    --policy-document "file://${ORDER_POLICY_FILE}" \
    --set-as-default
else
  aws iam create-policy \
    --policy-name OrderServicePolicy \
    --policy-document "file://${ORDER_POLICY_FILE}" \
    --tags "Key=project,Value=architecting-pro"
fi

# 3. Create IAM role with OIDC trust
create_or_update_role "eks-order-service-role" "order-service-sa"

# 4. Attach policy to role
aws iam attach-role-policy \
  --role-name    eks-order-service-role \
  --policy-arn   "${ORDER_POLICY_ARN}" 2>/dev/null || true

echo "  ✓ eks-order-service-role created and policy attached"
echo "    Role ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/eks-order-service-role"
rm -f "${ORDER_POLICY_FILE}"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  ✓ IRSA setup complete"
echo ""
echo "  Roles created:"
echo "    arn:aws:iam::${AWS_ACCOUNT_ID}:role/eks-product-service-role"
echo "    arn:aws:iam::${AWS_ACCOUNT_ID}:role/eks-order-service-role"
echo ""
echo "  NOTE: provider-service does not need IRSA."
echo "        It uses K8s Secret for RDS and EFS PVC for storage."
echo ""
echo "============================================================"

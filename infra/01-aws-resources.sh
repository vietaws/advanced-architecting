#!/usr/bin/env bash
# =============================================================================
# 01-aws-resources.sh — Provision AWS resources for the demo
#
# Creates:
#   - DynamoDB: products_table  (product-service)
#   - DynamoDB: orders_table    (order-service)
#   - S3 bucket: product images (product-service)
#   - SQS queue: orders         (order-service)
#
# Resources NOT created here (require EKS VPC — create after Phase 1):
#   - DAX cluster  → guides/phase-0-aws-resources.md Step 4
#   - RDS Aurora   → guides/phase-0-aws-resources.md Step 5
#   - EFS          → guides/phase-0-aws-resources.md Step 6
#
# Usage:
#   ./infra/01-aws-resources.sh
# =============================================================================
set -euo pipefail
export AWS_PAGER=""

REGION="ap-southeast-1"
DYNAMODB_PRODUCTS_TABLE="products_table"
DYNAMODB_ORDERS_TABLE="orders_table"
SQS_QUEUE_NAME="orders"

echo "============================================================"
echo "  Provisioning AWS resources"
echo "  Region: ${REGION}"
echo "============================================================"

# ── 1. DynamoDB — products_table ──────────────────────────────────────────────
echo ""
echo "[1/4] DynamoDB: ${DYNAMODB_PRODUCTS_TABLE}..."

if aws dynamodb describe-table \
  --table-name "${DYNAMODB_PRODUCTS_TABLE}" \
  --region "${REGION}" &>/dev/null; then
  echo "  Already exists: ${DYNAMODB_PRODUCTS_TABLE}"
else
  aws dynamodb create-table \
    --table-name "${DYNAMODB_PRODUCTS_TABLE}" \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"

  echo -n "  Waiting for ACTIVE... "
  aws dynamodb wait table-exists \
    --table-name "${DYNAMODB_PRODUCTS_TABLE}" \
    --region "${REGION}"
  echo "OK"
fi
echo "[1/4] ${DYNAMODB_PRODUCTS_TABLE} ready"

# ── 2. DynamoDB — orders_table ────────────────────────────────────────────────
echo ""
echo "[2/4] DynamoDB: ${DYNAMODB_ORDERS_TABLE}..."

if aws dynamodb describe-table \
  --table-name "${DYNAMODB_ORDERS_TABLE}" \
  --region "${REGION}" &>/dev/null; then
  echo "  Already exists: ${DYNAMODB_ORDERS_TABLE}"
else
  aws dynamodb create-table \
    --table-name "${DYNAMODB_ORDERS_TABLE}" \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"

  echo -n "  Waiting for ACTIVE... "
  aws dynamodb wait table-exists \
    --table-name "${DYNAMODB_ORDERS_TABLE}" \
    --region "${REGION}"
  echo "OK"
fi
echo "[2/4] ${DYNAMODB_ORDERS_TABLE} ready"

# ── 3. S3 bucket — product images ─────────────────────────────────────────────
echo ""
echo "[3/4] S3 bucket (product images)..."

EXISTING_BUCKET=$(aws s3api list-buckets \
  --query "Buckets[?starts_with(Name,'demo-product-images-')].Name" \
  --output text 2>/dev/null | awk '{print $1}')

if [[ -n "${EXISTING_BUCKET}" ]]; then
  PRODUCT_BUCKET="${EXISTING_BUCKET}"
  echo "  Already exists: ${PRODUCT_BUCKET}"
else
  PRODUCT_BUCKET="demo-product-images-$(openssl rand -hex 4)"
  aws s3api create-bucket \
    --bucket "${PRODUCT_BUCKET}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"

  aws s3api put-public-access-block \
    --bucket "${PRODUCT_BUCKET}" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  echo "  Created: ${PRODUCT_BUCKET}"
fi
echo "[3/4] S3 bucket ready: ${PRODUCT_BUCKET}"

# ── 4. SQS queue — orders ─────────────────────────────────────────────────────
echo ""
echo "[4/4] SQS queue: ${SQS_QUEUE_NAME}..."

SQS_QUEUE_URL=$(aws sqs get-queue-url \
  --queue-name "${SQS_QUEUE_NAME}" \
  --region "${REGION}" \
  --query QueueUrl --output text 2>/dev/null || true)

if [[ -n "${SQS_QUEUE_URL}" ]]; then
  echo "  Already exists: ${SQS_QUEUE_URL}"
else
  SQS_QUEUE_URL=$(aws sqs create-queue \
    --queue-name "${SQS_QUEUE_NAME}" \
    --attributes '{"VisibilityTimeout":"180"}' \
    --region "${REGION}" \
    --query QueueUrl --output text)
  echo "  Created: ${SQS_QUEUE_URL}"
fi
echo "[4/4] SQS queue ready"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  All resources ready. Export these before running"
echo "  03-oidc-irsa.sh and 04-k8s-setup.sh:"
echo ""
echo "  export PRODUCT_IMAGES_BUCKET=\"${PRODUCT_BUCKET}\""
echo "  export S3_BUCKET=\"${PRODUCT_BUCKET}\""
echo "  export SQS_QUEUE_URL=\"${SQS_QUEUE_URL}\""
echo "  export DYNAMODB_PRODUCTS_TABLE=\"${DYNAMODB_PRODUCTS_TABLE}\""
echo "  export DYNAMODB_ORDERS_TABLE=\"${DYNAMODB_ORDERS_TABLE}\""
echo ""
echo "  Resources requiring EKS VPC (create after Phase 1):"
echo "    DAX, RDS Aurora, EFS → see guides/phase-0-aws-resources.md"
echo "============================================================"

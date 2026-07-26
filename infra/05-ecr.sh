#!/usr/bin/env bash
# =============================================================================
# 05-ecr.sh — Create ECR repositories and build/push Docker images
#
# Can be run independently or before 04-k8s-setup.sh
#
# What this does:
#   1. Creates ECR repos for each service (idempotent)
#   2. Authenticates Docker to ECR
#   3. Builds multi-arch images (linux/arm64 for Graviton)
#   4. Pushes images to ECR with :latest and :<git-sha> tags
#
# Prerequisites:
#   - Docker Desktop with buildx enabled  (or docker buildx create)
#   - AWS CLI v2
#
# Usage:
#   chmod +x infra/05-ecr.sh
#   AWS_ACCOUNT_ID=123456789012 ./infra/05-ecr.sh
#
#   # Or build/push a single service only:
#   AWS_ACCOUNT_ID=123456789012 SERVICE=product-service ./infra/05-ecr.sh
# =============================================================================
set -euo pipefail

# ── Variables ─────────────────────────────────────────────────────────────────
REGION="ap-southeast-1"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
REPO_ROOT="$(dirname "$0")/.."

# Git SHA tag for immutable image versioning
GIT_SHA="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo 'local')"

# Services to build — override with SERVICE env var for a single service
ALL_SERVICES=("product-service" "provider-service" "order-service")
if [[ -n "${SERVICE:-}" ]]; then
  SERVICES=("${SERVICE}")
else
  SERVICES=("${ALL_SERVICES[@]}")
fi

# Target platform: linux/arm64 = Graviton (matches node group)
# Use linux/amd64 if running on x86 without cross-compilation support
PLATFORM="${PLATFORM:-linux/arm64}"

echo "============================================================"
echo "  ECR build & push"
echo "  Registry:  ${REGISTRY}"
echo "  Platform:  ${PLATFORM}"
echo "  Git SHA:   ${GIT_SHA}"
echo "  Services:  ${SERVICES[*]}"
echo "============================================================"

# ── Step 1: Authenticate Docker to ECR ───────────────────────────────────────
echo ""
echo "[1] Authenticating Docker to ECR..."
aws ecr get-login-password --region "${REGION}" | \
  docker login --username AWS --password-stdin "${REGISTRY}"
echo "    ✓ Authenticated"

# ── Step 2: Ensure buildx builder supports linux/arm64 ───────────────────────
echo ""
echo "[2] Ensuring buildx builder (multi-platform)..."
if ! docker buildx inspect architecting-pro-builder &>/dev/null; then
  docker buildx create \
    --name architecting-pro-builder \
    --driver docker-container \
    --platform linux/amd64,linux/arm64 \
    --use
fi
docker buildx use architecting-pro-builder
docker buildx inspect --bootstrap
echo "    ✓ Builder ready"

# ── Step 3: Create ECR repos + build + push ───────────────────────────────────
for SVC in "${SERVICES[@]}"; do
  echo ""
  echo "────────────────────────────────────────"
  echo "  Service: ${SVC}"
  echo "────────────────────────────────────────"

  # 3a. Create ECR repo if it doesn't exist
  if ! aws ecr describe-repositories \
        --repository-names "${SVC}" \
        --region "${REGION}" &>/dev/null; then
    echo "  Creating ECR repo: ${SVC}..."
    aws ecr create-repository \
      --repository-name "${SVC}" \
      --region "${REGION}" \
      --image-scanning-configuration scanOnPush=true \
      --encryption-configuration encryptionType=AES256 \
      --tags "Key=project,Value=architecting-pro"
    echo "  ✓ Repo created: ${REGISTRY}/${SVC}"
  else
    echo "  Repo already exists: ${REGISTRY}/${SVC}"
  fi

  # 3b. Build and push (single command with buildx)
  IMAGE="${REGISTRY}/${SVC}"
  echo "  Building ${IMAGE}:${GIT_SHA} (${PLATFORM})..."

  docker buildx build \
    --platform "${PLATFORM}" \
    --file     "${REPO_ROOT}/services/${SVC}/Dockerfile" \
    --tag      "${IMAGE}:latest" \
    --tag      "${IMAGE}:${GIT_SHA}" \
    --push \
    "${REPO_ROOT}/services/${SVC}"

  echo "  ✓ Pushed: ${IMAGE}:latest"
  echo "  ✓ Pushed: ${IMAGE}:${GIT_SHA}"
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  ✓ All images built and pushed"
echo ""
echo "  Images:"
for SVC in "${SERVICES[@]}"; do
  echo "    ${REGISTRY}/${SVC}:latest"
  echo "    ${REGISTRY}/${SVC}:${GIT_SHA}"
done
echo ""
echo "  Registry: ${REGISTRY}"
echo ""
echo "  Next step:  ./infra/04-k8s-setup.sh"
echo "============================================================"

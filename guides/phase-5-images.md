# Phase 4 — Container Images

> ← [Back to main guide](../README.md#deployment-workflow)

---

Build multi-platform images locally and push to Docker Hub and/or ECR. Images are built outside the EKS provisioning flow — run this before Phase 5.

---

## Image tags

| Service | Docker Hub | ECR |
|---|---|---|
| product-service | `vietaws/architecting-pro:product-service-latest` | `AWS_ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/product-service:latest` |
| provider-service | `vietaws/architecting-pro:provider-service-latest` | `AWS_ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/provider-service:latest` |
| order-service | `vietaws/architecting-pro:order-service-latest` | `AWS_ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/order-service:latest` |

---

## Platform support

Images are built for `linux/amd64,linux/arm64`. The correct variant is pulled automatically by the node group.

| Your machine | Build speed |
|---|---|
| Apple Silicon (M1/M2/M3/M4) | arm64 native — fast |
| Intel / AMD x86 | arm64 via QEMU emulation — slower |

---

## One-time setup

```bash
# Create buildx builder
docker buildx create \
  --name architecting-pro-builder \
  --driver docker-container \
  --platform linux/amd64,linux/arm64 \
  --use
docker buildx inspect --bootstrap

# Log in to Docker Hub
docker login

# Create ECR repositories
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGION="ap-southeast-1"

for SVC in product-service provider-service order-service; do
  aws ecr create-repository \
    --repository-name "${SVC}" \
    --region "${REGION}" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 \
    --tags "Key=project,Value=architecting-pro" \
    2>/dev/null && echo "✓ ${SVC}" || echo "  already exists: ${SVC}"
done
```

---

## Build and push

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGION="ap-southeast-1"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
DOCKER_HUB="vietaws/architecting-pro"

# Authenticate to ECR
aws ecr get-login-password --region "${REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

docker buildx use architecting-pro-builder
```

### All three services

```bash
for SVC in product-service provider-service order-service; do
  docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --file "services/${SVC}/Dockerfile" \
    --tag "${ECR_REGISTRY}/${SVC}:latest" \
    --tag "${DOCKER_HUB}:${SVC}-latest" \
    --push \
    "services/${SVC}"
done
```

### Single service

```bash
SVC=product-service   # change to provider-service or order-service
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --file "services/${SVC}/Dockerfile" \
  --tag "${ECR_REGISTRY}/${SVC}:latest" \
  --tag "${DOCKER_HUB}:${SVC}-latest" \
  --push \
  "services/${SVC}"
```

---

## Update deployment manifests

Edit `eks-setup/k8s/*/05-deployment.yaml` — set the `image:` field to your chosen registry before Phase 5. The `04-k8s-setup.sh` script substitutes the `AWS_ACCOUNT_ID` placeholder automatically for ECR images.

---

## Verify

```bash
REGION="ap-southeast-1"

# ECR
for SVC in product-service provider-service order-service; do
  aws ecr describe-images --repository-name "${SVC}" --region "${REGION}" \
    --query 'imageDetails[*].[imageTags[0],imagePushedAt]' --output table
done

# Docker Hub
curl -s "https://hub.docker.com/v2/repositories/vietaws/architecting-pro/tags" \
  | python3 -m json.tool | grep '"name"'
```

---

→ Next: [Phase 6 — Kubernetes Deploy](phase-6-deploy.md)

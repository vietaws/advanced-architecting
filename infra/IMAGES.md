# Container Image Build & Push Guide

This guide covers building multi-platform images locally and pushing them to both **Docker Hub** and **Amazon ECR**.

Images are built on your local machine using `docker buildx` and pushed independently of the EKS cluster provisioning.

---

## Services

| Service | Docker Hub | ECR |
|---|---|---|
| product-service | `vietaws/architecting-pro:product-service-latest` | `AWS_ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/product-service:latest` |
| provider-service | `vietaws/architecting-pro:provider-service-latest` | `AWS_ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/provider-service:latest` |
| order-service | `vietaws/architecting-pro:order-service-latest` | `AWS_ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/order-service:latest` |

---

## Prerequisites

- Docker Desktop >= 4.28 with `buildx` enabled
- AWS CLI v2 configured (`aws sts get-caller-identity` returns your account)
- Docker Hub account logged in (`docker login`)

---

## Platform support

The EKS node groups use **Graviton (linux/arm64)**. Building multi-platform images
lets the same tag serve both arm64 nodes and x86 developer machines.

| Your machine | Build speed |
|---|---|
| Apple Silicon (M1/M2/M3/M4) | arm64 native — fast |
| Intel / AMD x86 | arm64 via QEMU emulation — slower |

---

## One-time setup

### 1. Create a buildx builder

```bash
docker buildx create \
  --name architecting-pro-builder \
  --driver docker-container \
  --platform linux/amd64,linux/arm64 \
  --use

docker buildx inspect --bootstrap
```

### 2. Log in to Docker Hub

```bash
docker login
# Enter your Docker Hub username and password / access token
```

### 3. Create ECR repositories (one-time per account)

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGION="ap-southeast-1"

for SVC in product-service provider-service order-service; do
  aws ecr create-repository \
    --repository-name "${SVC}" \
    --region "${REGION}" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 \
    --tags "Key=project,Value=architecting-pro" \
    2>/dev/null && echo "✓ Created ECR repo: ${SVC}" \
    || echo "  Repo already exists: ${SVC}"
done
```

---

## Build and push

Set your account ID and authenticate to ECR, then build and push all three services:

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGION="ap-southeast-1"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
DOCKER_HUB="vietaws/architecting-pro"

# Authenticate Docker to ECR
aws ecr get-login-password --region "${REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# Use the multi-platform builder
docker buildx use architecting-pro-builder
```

### product-service

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --file services/product-service/Dockerfile \
  --tag "${ECR_REGISTRY}/product-service:latest" \
  --tag "${DOCKER_HUB}:product-service-latest" \
  --push \
  services/product-service
```

### provider-service

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --file services/provider-service/Dockerfile \
  --tag "${ECR_REGISTRY}/provider-service:latest" \
  --tag "${DOCKER_HUB}:provider-service-latest" \
  --push \
  services/provider-service
```

### order-service

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --file services/order-service/Dockerfile \
  --tag "${ECR_REGISTRY}/order-service:latest" \
  --tag "${DOCKER_HUB}:order-service-latest" \
  --push \
  services/order-service
```

---

## Build a single service

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

## Push to one registry only

### Docker Hub only

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --file services/product-service/Dockerfile \
  --tag "${DOCKER_HUB}:product-service-latest" \
  --push \
  services/product-service
```

### ECR only

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --file services/product-service/Dockerfile \
  --tag "${ECR_REGISTRY}/product-service:latest" \
  --push \
  services/product-service
```

---

## Verify pushed images

### Docker Hub

```bash
# List tags for the repo
curl -s "https://hub.docker.com/v2/repositories/vietaws/architecting-pro/tags" \
  | python3 -m json.tool | grep '"name"'
```

### ECR

```bash
for SVC in product-service provider-service order-service; do
  echo "── ${SVC}"
  aws ecr describe-images \
    --repository-name "${SVC}" \
    --region "${REGION}" \
    --query 'imageDetails[*].[imageTags[0],imagePushedAt]' \
    --output table
done
```

---

## Notes

- **DAX client**: `product-service` uses `amazon-dax-client` (CJS-only). The `Dockerfile` handles this — no changes needed.
- **EFS mount point**: `provider-service` `Dockerfile` runs `RUN mkdir -p /data/efs` so the PVC mount point exists before the volume is attached.
- **Image referenced in K8s**: `infra/eks-cluster/k8s/*/05-deployment.yaml` — update the `image:` field to point to your chosen registry (ECR or Docker Hub) before running `./infra/eks-cluster/04-k8s-setup.sh`.

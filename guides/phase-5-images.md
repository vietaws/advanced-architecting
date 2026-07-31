# Phase 5 — Container Images

> ← [Back to main guide](../README.md#deployment-workflow)

---

Build multi-platform images locally and push to **Docker Hub** first. Then re-tag and push the same images to **ECR** — no rebuild needed.

---

## Set your variables

Edit these once before running any commands below:

```bash
# Docker Hub (update your actual user and repo)
DOCKER_USER="vietaws"                  
DOCKER_REPO="architecting-pro"         

# AWS / ECR
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGION="ap-southeast-1"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
```

---

## Platform support

Images are built for `linux/amd64,linux/arm64`. The correct variant is pulled automatically by the node group.

| Your machine | Build speed |
|---|---|
| Apple Silicon (M1/M2/M3/M4) | arm64 native — fast |
| Intel / AMD x86 | arm64 via QEMU emulation — slower |

---

## One-time setup

Verify buildx is available (requires Docker Desktop >= 4.0):

```bash
docker buildx version
# Expected: github.com/docker/buildx v0.x.x ...
```

If the command is not found, update Docker Desktop and ensure it is running.

Create a multi-platform builder:

```bash
docker buildx create --use --name multiplatform-builder
docker buildx inspect --bootstrap
```

Log in to Docker Hub:

```bash
docker login
```

---

## Step 1 — Build and push to Docker Hub

```bash
docker buildx use multiplatform-builder

for SVC in product-service provider-service order-service; do
  docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --file "services/${SVC}/Dockerfile" \
    --tag "${DOCKER_USER}/${DOCKER_REPO}:${SVC}-latest" \
    --push \
    "services/${SVC}"
  echo "✓ Pushed ${DOCKER_USER}/${DOCKER_REPO}:${SVC}-latest"
done
```

Verify:

```bash
curl -s "https://hub.docker.com/v2/repositories/${DOCKER_USER}/${DOCKER_REPO}/tags" \
  | python3 -m json.tool | grep '"name"'
```

---

## Step 2 — Re-tag and push to ECR

No rebuild — pull the images from Docker Hub and push to ECR under the ECR tag.

```bash
# Authenticate Docker to ECR
aws ecr get-login-password --region "${REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# Create ECR repositories (skip if they already exist)
for SVC in product-service provider-service order-service; do
  aws ecr create-repository \
    --repository-name "${SVC}" \
    --region "${REGION}" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 \
    --tags "Key=project,Value=architecting-pro" \
    2>/dev/null && echo "✓ Created repo: ${SVC}" || echo "  Repo exists: ${SVC}"
done

# Pull from Docker Hub, re-tag, push to ECR
for SVC in product-service provider-service order-service; do
  docker pull "${DOCKER_USER}/${DOCKER_REPO}:${SVC}-latest"
  docker tag  "${DOCKER_USER}/${DOCKER_REPO}:${SVC}-latest" "${ECR_REGISTRY}/${SVC}:latest"
  docker push "${ECR_REGISTRY}/${SVC}:latest"
  echo "✓ Pushed ${ECR_REGISTRY}/${SVC}:latest"
done
```

Verify:

```bash
for SVC in product-service provider-service order-service; do
  echo "── ${SVC}"
  aws ecr describe-images --repository-name "${SVC}" --region "${REGION}" \
    --query 'imageDetails[*].[imageTags[0],imagePushedAt]' --output table
done
```

---

## Update deployment manifests

Edit `infra/k8s/*/05-deployment.yaml` — set the `image:` field to your chosen registry (ECR or Docker Hub) before Phase 6.

---

→ Next: [Phase 6 — Kubernetes Deploy](phase-6-deploy.md)

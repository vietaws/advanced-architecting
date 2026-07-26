# Implementation Guide

This guide walks through the complete implementation of the **Product-Provider Management** microservices on EKS — from architecture decisions down to individual files, commands, and verification steps.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Repository Map](#2-repository-map)
3. [Prerequisites](#3-prerequisites)
4. [Phase 0 — AWS Resources](#4-phase-0--aws-resources)
5. [Phase 1 — EKS Cluster](#5-phase-1--eks-cluster)
6. [Phase 2 — EKS Add-ons](#6-phase-2--eks-add-ons)
7. [Phase 3 — IAM & IRSA](#7-phase-3--iam--irsa)
8. [Phase 4 — Container Images](#8-phase-4--container-images)
9. [Phase 5 — Kubernetes Deploy](#9-phase-5--kubernetes-deploy)
10. [Phase 6 — Frontend](#10-phase-6--frontend)
11. [Verification](#11-verification)
12. [Teardown](#12-teardown)

---

## 1. Architecture Overview

```
Browser
  └── CloudFront ←── S3 (frontend/)
        │
        ▼  api.yourdomain.com
      ALB  (internet-facing, ap-southeast-1)
        │
    ┌───┴──────────────────────────────────────┐
    │  EKS Cluster — namespace: app            │
    │                                          │
    │  /products*   ──► product-service:3001   │
    │  /products-dax*    DynamoDB + DAX + S3   │
    │                                          │
    │  /providers*  ──► provider-service:3002  │
    │  /efs*             RDS Aurora + EFS PVC  │
    │                                          │
    │  /orders*     ──► order-service:3003     │
    │                    SQS + DynamoDB        │
    └──────────────────────────────────────────┘

AWS Managed Resources
  ├── DynamoDB:  products_table, orders_table
  ├── DAX:       dax-demo  (in-memory cache for products)
  ├── S3:        product image bucket (pre-signed URLs)
  ├── RDS:       Aurora PostgreSQL — providers_db
  ├── EFS:       shared volume — provider + EFS images
  └── SQS:       orders queue
```

### Key Design Decisions

| Decision | Choice | Reason |
|---|---|---|
| Runtime | Node.js 24 LTS (Krypton) ESM | Active LTS — supported until April 2028; matches codebase ESM style |
| Node architecture | Graviton ARM64 | ~20% better price/performance vs x86 |
| Capacity type | Spot instances | ~70% cost saving; pods are stateless |
| IAM auth | IRSA per service | Least privilege; no shared credentials |
| Shared storage | EFS PVC ReadWriteMany | provider-service shares volume across replicas |
| Config injection | K8s Secrets → envFrom | Simple; no extra dependencies for this lab |
| Frontend | S3 + CloudFront | Decoupled from backend; no CORS needed |

---

## 2. Repository Map

```
architecting-pro/
├── IMPLEMENTATION.md          ← this file
├── README.md                  ← project overview + quick-start
│
├── frontend/                  ← static SPA (deploy to S3)
│   ├── config.js              ← EDIT THIS: set API_URL to ALB endpoint
│   ├── index.html
│   ├── app.js
│   └── style.css
│
├── services/
│   ├── product-service/
│   │   ├── server.js          ← Express app, /health, /health/status
│   │   ├── logger.js          ← pino logger (service: product-service)
│   │   ├── Dockerfile         ← multi-stage, linux/arm64
│   │   ├── package.json
│   │   ├── .env.example
│   │   ├── db/
│   │   │   ├── dynamodb.js    ← DynamoDB document client
│   │   │   ├── s3.js          ← upload / presign / delete
│   │   │   └── dax.cjs        ← DAX client (CJS — amazon-dax-client)
│   │   └── routes/
│   │       ├── products.js    ← CRUD: GET/POST/PUT/DELETE /products
│   │       └── products-dax.cjs ← GET /products-dax (DAX read path)
│   │
│   ├── provider-service/
│   │   ├── server.js          ← Express app, mounts /providers + /efs
│   │   ├── logger.js
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   ├── .env.example
│   │   ├── db/
│   │   │   └── postgres.js    ← pg Pool → RDS Aurora
│   │   └── routes/
│   │       ├── providers.js   ← CRUD /providers + EFS image ops
│   │       └── efs.js         ← /efs file manager routes
│   │
│   └── order-service/
│       ├── server.js          ← Express app, /health/status
│       ├── logger.js
│       ├── Dockerfile
│       ├── package.json
│       ├── .env.example
│       ├── db/
│       │   ├── dynamodb.js    ← DynamoDB scan (orders_table)
│       │   └── sqs.js         ← SQS SendMessage
│       └── routes/
│           └── orders.js      ← POST /orders/generate, GET /orders
│
├── k8s/
│   ├── 01-namespace.yaml         ← namespace: app
│   ├── 02-efs-pvc.yaml           ← StorageClass + PV + PVC (efs-claim)
│   ├── 06-ingress.yaml           ← ALB ingress, path-based routing
│   ├── product-service/
│   │   ├── 03-serviceaccount.yaml  ← IRSA: eks-product-service-role
│   │   ├── 05-deployment.yaml      ← 2 replicas, envFrom secret
│   │   └── 04-service.yaml         ← ClusterIP :80 → :3001
│   ├── provider-service/
│   │   ├── 03-serviceaccount.yaml  ← no IRSA annotation
│   │   ├── 05-deployment.yaml      ← EFS volume mount at /data/efs
│   │   └── 04-service.yaml
│   └── order-service/
│       ├── 03-serviceaccount.yaml  ← IRSA: eks-order-service-role
│       ├── 05-deployment.yaml
│       └── 04-service.yaml
│
└── infra/
    ├── README.md              ← infra-specific detail
    ├── 01-cluster.sh          ← EKS cluster + Graviton node group
    ├── 02-addons.sh           ← CSI drivers + ALB Controller
    ├── 03-oidc-irsa.sh        ← IAM policies + IRSA roles
    ├── 04-k8s-setup.sh        ← namespace, PVC, secrets, deploy
    ├── 05-ecr.sh              ← ECR repos + docker buildx push
    └── iam/
        ├── product-service-policy.json
        ├── order-service-policy.json
        └── alb-controller-policy.json
```

---

## 3. Prerequisites

### Required tools

```bash
aws --version        # >= 2.15
eksctl version       # >= 0.180
kubectl version      # >= 1.29
helm version         # >= 3.14
docker --version     # >= 25 (Docker Desktop with buildx)
```

Install on macOS:
```bash
brew install awscli eksctl kubectl helm
# Docker Desktop: https://www.docker.com/products/docker-desktop
```

### AWS credentials

```bash
aws configure
aws sts get-caller-identity   # verify — must show correct account
```

Requires permissions on: EKS, EC2, IAM, ECR, DynamoDB, RDS, EFS, SQS, DAX, S3, CloudFront, ElasticLoadBalancing.

### VPC (must exist before running scripts)

| Subnet | CIDR | Tag required |
|---|---|---|
| public-1, public-2 | `10.1.1.0/24`, `10.1.2.0/24` | `kubernetes.io/role/elb=1` |
| app-1, app-2 | `10.1.3.0/24`, `10.1.4.0/24` | `kubernetes.io/role/internal-elb=1` |
| db-1, db-2 | `10.1.5.0/24`, `10.1.6.0/24` | (none required) |

You will need the **subnet IDs** for all four non-db subnets before running Phase 1.

---

## 4. Phase 0 — AWS Resources

Create all AWS-managed resources **before** deploying to EKS. The services depend on these at startup.

### 4.1 DynamoDB Tables

```bash
# products_table — used by product-service
aws dynamodb create-table \
  --table-name products_table \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-southeast-1

# orders_table — used by order-service
aws dynamodb create-table \
  --table-name orders_table \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-southeast-1
```

Referenced in:
- `services/product-service/db/dynamodb.js` → `process.env.DYNAMODB_PRODUCTS_TABLE`
- `services/order-service/db/dynamodb.js` → `process.env.DYNAMODB_ORDERS_TABLE`
- `k8s/product-service/05-deployment.yaml` → `product-service-secret`
- `k8s/order-service/05-deployment.yaml` → `order-service-secret`

### 4.2 S3 Bucket (product images)

```bash
PRODUCT_BUCKET="demo-product-images-$(openssl rand -hex 4)"
echo "Bucket name: $PRODUCT_BUCKET"   # save this value

aws s3api create-bucket \
  --bucket "$PRODUCT_BUCKET" \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1

# Block public access — product-service uses pre-signed URLs
aws s3api put-public-access-block \
  --bucket "$PRODUCT_BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

Referenced in:
- `services/product-service/db/s3.js` → `process.env.S3_BUCKET`
- `infra/iam/product-service-policy.json` → `PRODUCT_IMAGES_BUCKET` placeholder
- `infra/03-oidc-irsa.sh` → `PRODUCT_IMAGES_BUCKET` env var

### 4.3 SQS Queue

```bash
aws sqs create-queue \
  --queue-name orders \
  --attributes '{"VisibilityTimeout":"180"}' \
  --region ap-southeast-1

# Save the queue URL from the output
aws sqs get-queue-url --queue-name orders --region ap-southeast-1
```

Referenced in:
- `services/order-service/db/sqs.js` → `process.env.SQS_QUEUE_URL`
- `infra/iam/order-service-policy.json` → SQS resource ARN

### 4.4 DAX Cluster

DAX must be in the same VPC as EKS nodes (app subnets).

```bash
# Subnet group
aws dax create-subnet-group \
  --subnet-group-name dax-subnet-group \
  --subnet-ids subnet-APP1 subnet-APP2 \
  --region ap-southeast-1

# IAM role for DAX (allow DAX to call DynamoDB on your behalf)
# Use the AWS console or create a role with AmazonDynamoDBFullAccess

# DAX cluster
aws dax create-cluster \
  --cluster-name dax-demo \
  --node-type dax.r4.large \
  --replication-factor 1 \
  --iam-role-arn arn:aws:iam::AWS_ACCOUNT_ID:role/DAXRole \
  --subnet-group dax-subnet-group \
  --region ap-southeast-1

# Get the endpoint after ~10 min
aws dax describe-clusters --cluster-names dax-demo \
  --query 'Clusters[0].ClusterDiscoveryEndpoint'
```

Referenced in:
- `services/product-service/db/dax.cjs` → `process.env.DAX_ENDPOINT`
- `services/product-service/routes/products-dax.cjs` → DAX scan
- `services/product-service/server.js` → `/health/status` DAX check

### 4.5 RDS Aurora PostgreSQL

```bash
# Subnet group (db subnets)
aws rds create-db-subnet-group \
  --db-subnet-group-name demo-aurora-subnet-group \
  --db-subnet-group-description "Architecting Pro" \
  --subnet-ids subnet-DB1 subnet-DB2 \
  --region ap-southeast-1

# Cluster (Serverless v2 for cost efficiency in demo)
aws rds create-db-cluster \
  --db-cluster-identifier demo-aurora-cluster \
  --engine aurora-postgresql \
  --engine-version 16.2 \
  --master-username dbadmin \
  --master-user-password YourSecurePassword \
  --db-subnet-group-name demo-aurora-subnet-group \
  --vpc-security-group-ids sg-YOUR_APP_SG \
  --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=1 \
  --database-name providers_db \
  --no-deletion-protection \
  --region ap-southeast-1

# Instance
aws rds create-db-instance \
  --db-instance-identifier demo-aurora-instance \
  --db-cluster-identifier demo-aurora-cluster \
  --db-instance-class db.serverless \
  --engine aurora-postgresql \
  --no-publicly-accessible \
  --region ap-southeast-1
```

After the cluster is available, connect and create the schema:

```sql
-- Connect via psql or AWS Console Query Editor
CREATE TABLE IF NOT EXISTS providers (
  id             SERIAL PRIMARY KEY,
  name           VARCHAR(255) NOT NULL,
  city           VARCHAR(100),
  image_filename VARCHAR(255)
);

INSERT INTO providers (name, city) VALUES
  ('Viet AWS',      'Ho Chi Minh City'),
  ('Miracle Tech',  'Hanoi'),
  ('One Training',  'Da Nang');
```

Referenced in:
- `services/provider-service/db/postgres.js` → `RDS_HOST/PORT/DATABASE/USER/PASSWORD`
- `services/provider-service/server.js` → `/health/status` Aurora check

### 4.6 EFS File System

```bash
# Create EFS in the same VPC
EFS_ID=$(aws efs create-file-system \
  --performance-mode generalPurpose \
  --throughput-mode bursting \
  --tags Key=Name,Value=demo-efs \
  --region ap-southeast-1 \
  --query 'FileSystemId' --output text)

echo "EFS ID: $EFS_ID"   # save this — needed for k8s/02-efs-pvc.yaml

# Mount targets in each app subnet
aws efs create-mount-target \
  --file-system-id "$EFS_ID" \
  --subnet-id subnet-APP1 \
  --security-groups sg-YOUR_APP_SG \
  --region ap-southeast-1

aws efs create-mount-target \
  --file-system-id "$EFS_ID" \
  --subnet-id subnet-APP2 \
  --security-groups sg-YOUR_APP_SG \
  --region ap-southeast-1
```

Referenced in:
- `k8s/02-efs-pvc.yaml` → `EFS_FILE_SYSTEM_ID` placeholder (replaced by `04-k8s-setup.sh`)
- `k8s/provider-service/05-deployment.yaml` → PVC `efs-claim` mounted at `/data/efs`
- `services/provider-service/routes/providers.js` → `EFS_MOUNT_POINT = '/data/efs'`
- `services/provider-service/routes/efs.js` → same mount point


---

## 5. Phase 1 — EKS Cluster

**Script:** `infra/01-cluster.sh`

### What it does

1. Creates EKS control plane `demo-cluster` (K8s 1.30, ap-southeast-1)
2. Creates managed node group `app-nodes` with Graviton Spot instances
3. Tags public/private subnets for ALB discovery
4. Enables IAM OIDC provider (required for IRSA in Phase 3)

### Before running — edit subnet IDs

Open `infra/01-cluster.sh` and set these four variables:

```bash
SUBNET_APP_1="subnet-REPLACE_APP_1"   # app-1  10.1.3.0/24
SUBNET_APP_2="subnet-REPLACE_APP_2"   # app-2  10.1.4.0/24
SUBNET_PUB_1="subnet-REPLACE_PUB_1"   # public-1  10.1.1.0/24
SUBNET_PUB_2="subnet-REPLACE_PUB_2"   # public-2  10.1.2.0/24
```

### Run

```bash
chmod +x infra/*.sh
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

./infra/01-cluster.sh
```

### Node group spec

| Property | Value |
|---|---|
| Instance types | t4g.small → t4g.medium (Graviton2, burstable) |
| Architecture | linux/arm64 |
| Capacity | Spot |
| Min / Desired / Max | 1 / 1 / 2 |
| Volume | 20 GB gp3 |
| Subnets | app-1, app-2 (private) |

`t4g.small` (2 vCPU / 2 GB) is sufficient for this demo: 6 pods × 64Mi request = 384Mi + ~300Mi system ≈ 700Mi total. For production or load testing, switch to `m8g.large,m7g.large,m6g.large` in `01-cluster.sh`.

### Expected output

```
[✓] EKS cluster demo-cluster created
[✓] Node group app-nodes created
[✓] Subnets tagged
[✓] OIDC provider enabled
OIDC ID: <32-char hex string>
```

Verify:
```bash
kubectl get nodes -o wide
# Should show 2 nodes, arm64 architecture
```

---

## 6. Phase 2 — EKS Add-ons

**Script:** `infra/02-addons.sh`

### What it installs

| Add-on | Method | IRSA |
|---|---|---|
| kube-proxy | EKS managed | No |
| CoreDNS | EKS managed | No |
| aws-ebs-csi-driver | EKS managed | Yes — `AmazonEBSCSIDriverPolicy` |
| aws-efs-csi-driver | EKS managed | Yes — `AmazonEFSCSIDriverPolicy` (inline JSON) |
| aws-load-balancer-controller | Helm v1.8.1 | Yes — `infra/iam/alb-controller-policy.json` |

### The ALB Controller policy

File: `infra/iam/alb-controller-policy.json`

This is the official AWS Load Balancer Controller v2 minimal policy. It is scoped with conditions so it only manages resources tagged with `elbv2.k8s.aws/cluster`. Key permissions:
- `elasticloadbalancing:Create/Delete/Modify*` — ALB lifecycle
- `ec2:CreateSecurityGroup`, `ec2:AuthorizeSecurityGroupIngress` — security groups for ALB
- `acm:DescribeCertificate` — HTTPS certificate lookup

### Run

```bash
./infra/02-addons.sh
```

### Expected output

```
[1/5] ✓ kube-proxy installed
[2/5] ✓ CoreDNS installed
[3/5] ✓ EBS CSI driver installed
[4/5] ✓ EFS CSI driver installed
[5/5] ✓ AWS Load Balancer Controller installed
```

Verify:
```bash
kubectl get pods -n kube-system | grep -E "coredns|ebs-csi|efs-csi|aws-load-balancer"
# All pods should be Running
```


---

## 7. Phase 3 — IAM & IRSA

**Script:** `infra/03-oidc-irsa.sh`

IRSA (IAM Roles for Service Accounts) lets each pod assume an IAM role without static credentials. The OIDC provider (created in Phase 1) bridges K8s service accounts to IAM roles.

### How IRSA works

```
Pod starts
  └── K8s injects a signed OIDC token into the pod
        └── AWS SDK exchanges token for temporary credentials
              └── via sts:AssumeRoleWithWebIdentity
                    └── IAM role trust policy validates:
                          - correct OIDC issuer
                          - correct namespace:serviceaccount
```

### Service accounts and roles

| Service | K8s ServiceAccount | IAM Role | Policy file |
|---|---|---|---|
| product-service | `product-service-sa` | `eks-product-service-role` | `iam/product-service-policy.json` |
| order-service | `order-service-sa` | `eks-order-service-role` | `iam/order-service-policy.json` |
| provider-service | `provider-service-sa` | — none — | (uses K8s Secret for RDS, PVC for EFS) |

### product-service permissions — `infra/iam/product-service-policy.json`

| Sid | Resource | Actions |
|---|---|---|
| DynamoDBProductsTable | `products_table` | Scan, PutItem, GetItem, UpdateItem, DeleteItem, DescribeTable |
| DAXProductsCluster | `dax-demo` | GetItem, Scan, Query, BatchGet/Write, Put/Update/Delete |
| S3ProductImagesObjects | `bucket/products/*` | PutObject, GetObject, DeleteObject |
| S3ProductImagesBucket | `bucket` | HeadBucket, ListBucket |

Used by:
- `services/product-service/db/dynamodb.js` — DynamoDB operations
- `services/product-service/db/s3.js` — image upload/presign/delete
- `services/product-service/db/dax.cjs` — DAX scan
- `services/product-service/server.js` — `/health/status` (DescribeTable + HeadBucket)

### order-service permissions — `infra/iam/order-service-policy.json`

| Sid | Resource | Actions |
|---|---|---|
| SQSOrdersQueue | `orders` queue | SendMessage, GetQueueAttributes, GetQueueUrl |
| DynamoDBOrdersTable | `orders_table` | Scan, DescribeTable |

Used by:
- `services/order-service/db/sqs.js` — SendMessage
- `services/order-service/db/dynamodb.js` — Scan
- `services/order-service/server.js` — `/health/status` (GetQueueAttributes + DescribeTable)

### IRSA annotation in K8s manifests

The role ARN is annotated on each ServiceAccount. These files are patched with the real account ID by `04-k8s-setup.sh`:

`k8s/product-service/03-serviceaccount.yaml`:
```yaml
annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::AWS_ACCOUNT_ID:role/eks-product-service-role
```

`k8s/order-service/03-serviceaccount.yaml`:
```yaml
annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::AWS_ACCOUNT_ID:role/eks-order-service-role
```

`k8s/provider-service/03-serviceaccount.yaml` has no annotation — intentional.

### Run

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export PRODUCT_IMAGES_BUCKET="demo-product-images-xxxx"   # your actual bucket name

./infra/03-oidc-irsa.sh
```

The script:
1. Resolves the OIDC ID from the cluster
2. Renders policy JSON (substitutes `AWS_ACCOUNT_ID` and `PRODUCT_IMAGES_BUCKET` placeholders)
3. Creates or updates `ProductServicePolicy` and `OrderServicePolicy`
4. Creates IAM roles with trust policies scoped to `system:serviceaccount:app:<sa-name>`
5. Attaches policies to roles

### Verify

```bash
aws iam get-role --role-name eks-product-service-role \
  --query 'Role.AssumeRolePolicyDocument'

aws iam list-attached-role-policies --role-name eks-product-service-role
```


---

## 8. Phase 4 — Container Images

**Script:** `infra/05-ecr.sh`

### Dockerfiles

Each service has its own multi-stage Dockerfile. Example structure (`services/product-service/Dockerfile`):

> **Base image:** `node:24-alpine` — Node.js 24 "Krypton" is the current Active LTS (supported until April 2028). Alpine keeps the image small (~180 MB vs ~1 GB for the full Debian image). Tag `node:24-alpine` always resolves to the latest Alpine 3.x for Node 24 — pin to `node:24.18.0-alpine3.24` for fully reproducible builds.

```dockerfile
# Stage 1: install prod dependencies only
FROM node:24-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Stage 2: minimal runtime image
FROM node:24-alpine
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY . .
USER node           # non-root
EXPOSE 3001
CMD ["node", "server.js"]
```

`provider-service` Dockerfile also runs `RUN mkdir -p /data/efs` so the mount point exists before the PVC is attached.

### Build target: linux/arm64

Images must match the Graviton (ARM64) node group. The script uses `docker buildx`:

```bash
docker buildx build \
  --platform linux/arm64 \
  --file services/product-service/Dockerfile \
  --tag $REGISTRY/product-service:latest \
  --push \
  services/product-service
```

If building on an Apple Silicon Mac, `linux/arm64` is native — fast builds, no emulation.  
If building on x86 without QEMU, set `PLATFORM=linux/amd64` and update the node group instance type to x86.

### Run

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

./infra/05-ecr.sh
```

The script:
1. Creates ECR repos (scan-on-push enabled, AES256 encryption) for each service
2. Creates a `docker buildx` builder for multi-platform support
3. Builds and pushes `linux/arm64` images tagged `:latest` and `:<git-sha>`

### Single service rebuild

```bash
SERVICE=product-service ./infra/05-ecr.sh
```

### ECR repos created

```
AWS_ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/product-service
AWS_ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/provider-service
AWS_ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/order-service
```

Referenced in `k8s/*/05-deployment.yaml` — the `AWS_ACCOUNT_ID` placeholder is replaced by `04-k8s-setup.sh`.

### DAX client note

`product-service` uses `amazon-dax-client` (v1, CJS-only). The `products-dax.cjs` route and `db/dax.cjs` are loaded via `createRequire()` in `server.js`. This is a known constraint of the DAX SDK — it cannot be imported as ESM.


---

## 9. Phase 5 — Kubernetes Deploy

**Script:** `infra/04-k8s-setup.sh`

### What it applies

```
k8s/01-namespace.yaml              → creates namespace "app"
k8s/02-efs-pvc.yaml                → StorageClass + PV + PVC
k8s/*/03-serviceaccount.yaml       → 3 service accounts (2 with IRSA)
k8s/*/05-deployment.yaml           → 3 deployments (2 replicas each)
k8s/*/04-service.yaml              → 3 ClusterIP services
k8s/06-ingress.yaml                → ALB ingress
```

### K8s Secrets

The script creates three secrets, one per service, using `kubectl create secret --dry-run=client | kubectl apply`. This makes the command idempotent (safe to re-run):

**product-service-secret** — consumed by `k8s/product-service/05-deployment.yaml`:
```
AWS_REGION, DYNAMODB_PRODUCTS_TABLE, DAX_ENDPOINT, S3_BUCKET
```

**provider-service-secret** — consumed by `k8s/provider-service/05-deployment.yaml`:
```
AWS_REGION, RDS_HOST, RDS_PORT, RDS_DATABASE, RDS_USER, RDS_PASSWORD
```

**order-service-secret** — consumed by `k8s/order-service/05-deployment.yaml`:
```
AWS_REGION, DYNAMODB_ORDERS_TABLE, SQS_QUEUE_URL
```

All injected into pods via `envFrom.secretRef` — no hardcoded credentials in manifests.

### EFS PVC

`k8s/02-efs-pvc.yaml` defines three objects:

1. **StorageClass** `efs-sc` — driver: `efs.csi.aws.com`, reclaimPolicy: Retain
2. **PersistentVolume** `efs-pv` — 5Gi ReadWriteMany, volumeHandle: `EFS_FILE_SYSTEM_ID`
3. **PersistentVolumeClaim** `efs-claim` — namespace: app, bound to `efs-pv`

The script replaces `EFS_FILE_SYSTEM_ID` with the real value from `$EFS_FILE_SYSTEM_ID` env var before applying.

Only `provider-service` mounts this PVC (at `/data/efs`). It serves both `/providers/image/:filename` and `/efs/image/:filename` from the same volume.

### Ingress (ALB)

`k8s/06-ingress.yaml` creates an internet-facing ALB via the AWS Load Balancer Controller:

```yaml
annotations:
  kubernetes.io/ingress.class: alb
  alb.ingress.kubernetes.io/scheme: internet-facing
  alb.ingress.kubernetes.io/target-type: ip      # pods directly, no NodePort
  alb.ingress.kubernetes.io/ssl-redirect: "443"
  alb.ingress.kubernetes.io/group.name: app
```

Path routing (order matters — more specific first):

| Path | Service | Port |
|---|---|---|
| `/products-dax` | product-service | 80 |
| `/products` | product-service | 80 |
| `/providers/health` | provider-service | 80 |
| `/providers` | provider-service | 80 |
| `/efs` | provider-service | 80 |
| `/orders` | order-service | 80 |

`/products-dax` is listed before `/products` to avoid prefix match shadowing. Same pattern for `/providers/health` before `/providers`.

### Health probes

Each deployment has liveness and readiness probes on `GET /health`:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 3001
  initialDelaySeconds: 10
  periodSeconds: 15
  failureThreshold: 3
```

Each service's `/health` returns `{ status: "healthy", service: "<name>" }` immediately without any backend checks — suitable for K8s probes which should not block on DB connectivity.

The deeper check `GET /health/status` is for the dashboard only:
- `GET /products/health/status` → checks DynamoDB, DAX, S3
- `GET /providers/health/status` → checks Aurora, EFS
- `GET /orders/health/status` → checks SQS, DynamoDB

### Run

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export EFS_FILE_SYSTEM_ID="fs-0123456789abcdef0"
export DAX_ENDPOINT="daxs://xxx.dax-clusters.ap-southeast-1.amazonaws.com"
export S3_BUCKET="demo-product-images-xxxx"
export RDS_HOST="demo-aurora-cluster.cluster-xxx.ap-southeast-1.rds.amazonaws.com"
export RDS_PASSWORD="YourSecurePassword"
export SQS_QUEUE_URL="https://sqs.ap-southeast-1.amazonaws.com/AWS_ACCOUNT_ID/orders"

./infra/04-k8s-setup.sh
```

### Expected output

```
[1/5] ✓ Namespace 'app' ready
[2/5] ✓ ServiceAccount ARNs and image URIs patched
[3/5] ✓ EFS PVC 'efs-claim' created
[4/5] ✓ K8s Secrets created
[5/5] ✓ All manifests applied
✓ Deployment complete

NAME                    READY   STATUS    RESTARTS   AGE
product-service-xxx     1/1     Running   0          60s
provider-service-xxx    1/1     Running   0          60s
order-service-xxx       1/1     Running   0          60s
```


---

## 10. Phase 6 — Frontend

The frontend is a vanilla JS SPA with no build step — four static files deployed directly to S3.

### Files

| File | Purpose |
|---|---|
| `frontend/config.js` | Sets `window.APP_CONFIG.API_URL` — the only file to edit per environment |
| `frontend/index.html` | SPA shell — loads `config.js` then `app.js` in order |
| `frontend/app.js` | All UI logic — reads `API_URL` from `window.APP_CONFIG` |
| `frontend/style.css` | Styles |

### Step 1 — Set the API URL

Edit `frontend/config.js`:

```js
window.APP_CONFIG = {
  API_URL: 'https://api.yourdomain.com',  // ALB DNS or custom domain
};
```

The ALB DNS is available after Phase 5:
```bash
kubectl get ingress app-ingress -n app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

`app.js` falls back to `window.location.origin` if `APP_CONFIG` is not set — safe for local dev.

### Step 2 — Create S3 bucket

```bash
FRONTEND_BUCKET="demo-frontend-$(openssl rand -hex 4)"

aws s3api create-bucket \
  --bucket "$FRONTEND_BUCKET" \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1

aws s3api put-public-access-block \
  --bucket "$FRONTEND_BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

### Step 3 — Upload

```bash
aws s3 sync frontend/ s3://$FRONTEND_BUCKET --delete
```

### Step 4 — CloudFront distribution

```bash
aws cloudfront create-distribution \
  --origin-domain-name "${FRONTEND_BUCKET}.s3.ap-southeast-1.amazonaws.com" \
  --default-root-object index.html
```

Use **Origin Access Control (OAC)** to give CloudFront read access to the private S3 bucket without making the bucket public.

### Step 5 — Update after changes

After any frontend file change:
```bash
# Re-upload
aws s3 sync frontend/ s3://$FRONTEND_BUCKET --delete

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id YOUR_DISTRIBUTION_ID \
  --paths "/*"
```

### How the dashboard works

`frontend/app.js` — `loadDashboard()` fires three parallel fetches:

```
fetch /products/health/status  → product-service → { dynamodb, dax, s3 }
fetch /providers/health/status → provider-service → { aurora, efs }
fetch /orders/health/status    → order-service   → { sqs, dynamodb }
```

Results are merged and rendered into six status cards on the home tab. Each service's `/health/status` handler lives in `services/*/server.js`.

---

## 11. Verification

### Cluster

```bash
# Nodes — should show arm64 architecture
kubectl get nodes -o wide

# Add-ons
kubectl get pods -n kube-system
```

### Services

```bash
# All pods Running — expect 6 total (2 per service)
kubectl get pods -n app -o wide

# Services
kubectl get svc -n app
```

### Ingress / ALB

```bash
# ALB address (takes ~2 min to provision after first apply)
kubectl get ingress app-ingress -n app

ALB=$(kubectl get ingress app-ingress -n app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB: $ALB"
```

### Health endpoints

```bash
# Liveness probes
curl -s http://$ALB/products/health | jq .
curl -s http://$ALB/providers/health | jq .
curl -s http://$ALB/orders/health | jq .

# Deep connectivity checks
curl -s http://$ALB/products/health/status | jq .
curl -s http://$ALB/providers/health/status | jq .
curl -s http://$ALB/orders/health/status | jq .
```

Expected response for a healthy deployment:
```json
// /products/health/status
{ "dynamodb": { "status": "connected" }, "dax": { "status": "connected" }, "s3": { "status": "connected" } }

// /providers/health/status
{ "aurora": { "status": "connected" }, "efs": { "status": "connected" } }

// /orders/health/status
{ "sqs": { "status": "connected" }, "dynamodb": { "status": "connected" } }
```

### API smoke tests

```bash
# List products (DynamoDB)
curl -s http://$ALB/products | jq 'length'

# List products (DAX)
curl -s http://$ALB/products-dax | jq 'length'

# List providers
curl -s http://$ALB/providers | jq '.[].name'

# Generate orders → SQS
curl -s -X POST http://$ALB/orders/generate | jq .

# List orders from DynamoDB
curl -s http://$ALB/orders | jq 'length'
```

### IRSA verification

```bash
# Exec into a pod and confirm the role is assumed
kubectl exec -n app \
  $(kubectl get pod -n app -l app=product-service -o jsonpath='{.items[0].metadata.name}') \
  -- env | grep AWS_ROLE_ARN
# Should print: AWS_ROLE_ARN=arn:aws:iam::ACCOUNT_ID:role/eks-product-service-role
```

---

## 12. Teardown

```bash
# 1. Delete K8s resources
kubectl delete namespace app
kubectl delete -f k8s/02-efs-pvc.yaml

# 2. Delete cluster (removes node group, OIDC provider, VPC tags)
eksctl delete cluster --name demo-cluster --region ap-southeast-1

# 3. Delete IAM roles and policies
for ROLE in eks-product-service-role eks-order-service-role; do
  aws iam list-attached-role-policies --role-name $ROLE \
    --query 'AttachedPolicies[*].PolicyArn' --output text | \
    xargs -I {} aws iam detach-role-policy --role-name $ROLE --policy-arn {}
  aws iam delete-role --role-name $ROLE
done

aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ProductServicePolicy
aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/OrderServicePolicy
aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy
aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AmazonEFSCSIDriverPolicy

# 4. Delete ECR repos
for REPO in product-service provider-service order-service; do
  aws ecr delete-repository --repository-name $REPO --force --region ap-southeast-1
done

# 5. Delete AWS resources (optional — incur cost if left running)
aws dynamodb delete-table --table-name products_table --region ap-southeast-1
aws dynamodb delete-table --table-name orders_table --region ap-southeast-1
aws sqs delete-queue --queue-url $SQS_QUEUE_URL --region ap-southeast-1
aws dax delete-cluster --cluster-name dax-demo --region ap-southeast-1
aws rds delete-db-instance --db-instance-identifier demo-aurora-instance \
  --skip-final-snapshot --region ap-southeast-1
aws rds delete-db-cluster --db-cluster-identifier demo-aurora-cluster \
  --skip-final-snapshot --region ap-southeast-1
aws efs delete-file-system --file-system-id $EFS_FILE_SYSTEM_ID --region ap-southeast-1
aws s3 rb s3://$PRODUCT_BUCKET --force
aws s3 rb s3://$FRONTEND_BUCKET --force
```

---

## 13. Local Development

Run services individually against real AWS resources (or LocalStack) using `.env.example` as a template.

### Setup

```bash
cd services/product-service
cp .env.example .env
# Edit .env with real values
npm install
npm start
```

Each service's `.env.example` documents all required variables:

| Service | File | Key variables |
|---|---|---|
| product-service | `services/product-service/.env.example` | `DYNAMODB_PRODUCTS_TABLE`, `DAX_ENDPOINT`, `S3_BUCKET` |
| provider-service | `services/provider-service/.env.example` | `RDS_HOST`, `RDS_DATABASE`, `RDS_USER`, `RDS_PASSWORD` |
| order-service | `services/order-service/.env.example` | `DYNAMODB_ORDERS_TABLE`, `SQS_QUEUE_URL` |

### Ports

| Service | Port |
|---|---|
| product-service | 3001 |
| provider-service | 3002 |
| order-service | 3003 |

### Logging

Each service uses `pino` with `pino-pretty` in development mode. Set `NODE_ENV=development` in `.env` for coloured, human-readable logs. In production (K8s), pino outputs structured JSON — collected by CloudWatch Container Insights.

### DAX in local dev

DAX requires VPC network access. If developing outside AWS, skip DAX and test via the regular DynamoDB route (`GET /products`). The DAX route (`GET /products-dax`) will return an error when `DAX_ENDPOINT` is unreachable — this is expected.

---

## Related documents

| Document | Location | Purpose |
|---|---|---|
| Project overview | [`README.md`](README.md) | Architecture diagram, service summary, API reference |
| Infra scripts detail | [`infra/README.md`](infra/README.md) | Script-by-script reference, node group rationale, IAM tables |
| This guide | `IMPLEMENTATION.md` | End-to-end walkthrough with file references |

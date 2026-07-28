# Architecting Pro — Microservices on EKS

A **monolith-to-microservices migration** demo for the AWS Solutions Architect Pro lab.  
Three Node.js services run on **Amazon EKS**, fronted by an **AWS ALB** and a **CloudFront + S3** static frontend.

---

## Architecture

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
  ├── DAX:       dax-demo  (read-through cache for products)
  ├── S3:        product image bucket (pre-signed URLs)
  ├── RDS:       Aurora PostgreSQL — providers_db
  ├── EFS:       shared volume — provider images
  └── SQS:       orders queue
```

### Key design decisions

| Decision | Choice | Reason |
|---|---|---|
| Runtime | Node.js 24 LTS ESM | Active LTS until April 2028 |
| Node architecture | Graviton ARM64 (t4g.medium) | ~20% better price/performance vs x86 |
| Capacity type | Spot instances | ~70% cost saving; pods are stateless |
| IAM auth | IRSA per service | Least privilege; no shared credentials |
| Shared storage | EFS PVC ReadWriteMany | provider-service shares volume across replicas |
| Config injection | K8s Secrets → envFrom | No hardcoded credentials in manifests |
| Frontend | S3 + CloudFront | Decoupled from backend; deploy before backend exists |

---

## Repository Structure

```
architecting-pro/
├── README.md                      ← this file
│
├── frontend/                      ← static SPA (S3 + CloudFront)
│   ├── config.js                  ← EDIT THIS: set API_URL to ALB endpoint
│   ├── index.html
│   ├── app.js
│   └── style.css
│
├── services/
│   ├── product-service/           ← DynamoDB + DAX + S3  (port 3001)
│   ├── provider-service/          ← RDS Aurora + EFS     (port 3002)
│   └── order-service/             ← SQS + DynamoDB       (port 3003)
│
└── infra/                         ← all infrastructure docs and scripts
    ├── README.md                  ← navigation index
    ├── IMAGES.md                  ← container image build & push
    ├── VERIFICATION.md            ← post-deploy verification checklist
    ├── TEARDOWN.md                ← delete all resources
    ├── aws-resources/
    │   └── README.md              ← Phase 0: DynamoDB, S3, SQS, DAX, Aurora, EFS
    └── eks-cluster/
        ├── README.md              ← Phases 1–5: EKS, add-ons, IRSA, deploy
        ├── 02-addons.sh
        ├── 03-oidc-irsa.sh
        ├── 04-k8s-setup.sh
        ├── iam/                   ← least-privilege IAM policy documents
        └── k8s/                   ← Kubernetes manifests
```

---

## Prerequisites

```bash
aws --version        # >= 2.15
eksctl version       # >= 0.180
kubectl version      # >= 1.29
helm version         # >= 3.14
docker --version     # >= 25 (Docker Desktop with buildx)
```

```bash
brew install awscli eksctl kubectl helm
```

AWS credentials must have permissions on: EKS, EC2, IAM, ECR, DynamoDB, RDS, EFS, SQS, DAX, S3, CloudFront, ElasticLoadBalancing.

---

## Deployment Workflow

### Phase 0 — AWS Resources

Create all AWS-managed resources **before** provisioning EKS. Services depend on these at startup.

| Resource | Used by |
|---|---|
| DynamoDB `products_table` | product-service |
| DynamoDB `orders_table` | order-service |
| S3 bucket (product images) | product-service |
| SQS queue `orders` | order-service |
| DAX cluster `dax-demo` | product-service |
| RDS Aurora PostgreSQL `providers_db` | provider-service |
| EFS file system | provider-service |

→ **[Full CLI commands: infra/aws-resources/README.md](infra/aws-resources/README.md)**

---

### Phase 1 — EKS Cluster

One command creates the control plane, a new VPC (`10.2.0.0/16`), public + private subnets in 2 AZs, subnet tags for ALB, and the IAM OIDC provider.

```bash
eksctl create cluster \
  --name demo-cluster \
  --region ap-southeast-1 \
  --version 1.30 \
  --vpc-cidr 10.2.0.0/16 \
  --zones ap-southeast-1a,ap-southeast-1b \
  --without-nodegroup \
  --with-oidc \
  --tags "project=architecting-pro,env=demo"
```

Then add a node group — **public** (no NAT cost) or **private** (with NAT Gateway):

→ **[Full node group commands: infra/eks-cluster/README.md](infra/eks-cluster/README.md#phase-1--eks-cluster)**

---

### Phase 2 — EKS Add-ons

```bash
./infra/eks-cluster/02-addons.sh
```

Installs: EBS CSI driver, EFS CSI driver, CoreDNS, kube-proxy, AWS Load Balancer Controller.

→ **[Detail: infra/eks-cluster/README.md](infra/eks-cluster/README.md#phase-2--eks-add-ons)**

---

### Phase 3 — IAM & IRSA

```bash
export PRODUCT_IMAGES_BUCKET="demo-product-images-xxxx"
./infra/eks-cluster/03-oidc-irsa.sh
```

Creates least-privilege IAM roles for `product-service` (DynamoDB, DAX, S3) and `order-service` (SQS, DynamoDB). `provider-service` needs no IRSA — RDS via K8s Secret, EFS via PVC.

→ **[Detail: infra/eks-cluster/README.md](infra/eks-cluster/README.md#phase-3--iam--irsa)**

---

### Phase 4 — Container Images

Build multi-platform images (`linux/amd64,linux/arm64`) locally and push to Docker Hub and/or ECR.

→ **[Build & push guide: infra/IMAGES.md](infra/IMAGES.md)**

---

### Phase 5 — Kubernetes Deploy

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export EFS_FILE_SYSTEM_ID="fs-xxxx"
export DAX_ENDPOINT="daxs://..."
export S3_BUCKET="demo-product-images-xxxx"
export RDS_HOST="demo-aurora-cluster.cluster-xxx.ap-southeast-1.rds.amazonaws.com"
export RDS_PASSWORD="..."
export SQS_QUEUE_URL="https://sqs.ap-southeast-1.amazonaws.com/ACCOUNT/orders"

./infra/eks-cluster/04-k8s-setup.sh
```

Applies namespace, EFS PVC, ServiceAccounts, Deployments, Services, and ALB Ingress.

→ **[Detail: infra/eks-cluster/README.md](infra/eks-cluster/README.md#phase-5--kubernetes-deploy)**

---

### Phase 6 — Frontend

Deploy the static SPA to S3 + CloudFront. You can do this **before any backend exists** — the dashboard shows all resources as **Disconnected** (red) until services come online.

#### Configure API endpoint

Edit `frontend/config.js`:

```js
window.APP_CONFIG = {
  // Leave empty for frontend-only deploy (all resources show Disconnected).
  // Set to your ALB DNS once the backend is deployed.
  API_URL: '',
};
```

#### Create S3 bucket

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

#### Upload and create CloudFront distribution

```bash
aws s3 sync frontend/ s3://$FRONTEND_BUCKET --delete

aws cloudfront create-distribution \
  --origin-domain-name "${FRONTEND_BUCKET}.s3.ap-southeast-1.amazonaws.com" \
  --default-root-object index.html
```

Use **Origin Access Control (OAC)** so CloudFront can read the private S3 bucket.

#### Activate backend (after Phase 5)

```bash
# Get ALB DNS
ALB=$(kubectl get ingress app-ingress -n app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Set API_URL in config.js, re-upload, invalidate cache
vi frontend/config.js
aws s3 cp frontend/config.js s3://$FRONTEND_BUCKET/config.js
aws cloudfront create-invalidation \
  --distribution-id YOUR_DISTRIBUTION_ID \
  --paths "/config.js"
```

#### Dashboard — infrastructure status cards

The home tab shows one card per service. Status is checked on page load or **↻ Refresh** via `GET /health/status`.

| Card | Resources checked |
|---|---|
| Product Service | DynamoDB, DAX, S3 |
| Provider Service | Aurora (RDS), EFS |
| Order Service | SQS |

---

## Services Reference

### product-service (port 3001)

| Item | Detail |
|---|---|
| Routes | `GET/POST/PUT/DELETE /products`, `GET /products-dax` |
| DynamoDB | `products_table` — Scan, PutItem, GetItem, UpdateItem, DeleteItem |
| DAX | Read-through cache via `amazon-dax-client` |
| S3 | Product image upload/download/delete (pre-signed URLs) |
| IRSA | `dynamodb:Scan/PutItem/GetItem/UpdateItem/DeleteItem`, `dax:GetItem/Scan`, `s3:PutObject/GetObject/DeleteObject` |

### provider-service (port 3002)

| Item | Detail |
|---|---|
| Routes | `GET/POST/PUT/DELETE /providers`, `GET /providers/image/:filename`, `GET /efs`, `POST /efs/upload`, `GET /efs/image/:filename`, `DELETE /efs/:filename` |
| Database | RDS Aurora PostgreSQL — `providers` table in `providers_db` |
| Storage | EFS PVC at `/data/efs` — serves both provider images and `/efs` file manager |
| IRSA | None — RDS via K8s Secret, EFS via PVC |

### order-service (port 3003)

| Item | Detail |
|---|---|
| Routes | `POST /orders/generate`, `GET /orders` |
| SQS | Publishes 10 orders per batch to `orders` queue |
| DynamoDB | `orders_table` — Scan to list orders |
| IRSA | `sqs:SendMessage/GetQueueAttributes`, `dynamodb:Scan` |

---

## API Reference

### product-service (`/products`)

| Method | Path | Description |
|---|---|---|
| GET | `/products` | List all products (DynamoDB) |
| GET | `/products-dax` | List all products (DAX cache) |
| POST | `/products` | Create product (optional image upload) |
| PUT | `/products/:id` | Update product |
| DELETE | `/products/:id` | Delete product + S3 image |

### provider-service (`/providers` + `/efs`)

| Method | Path | Description |
|---|---|---|
| GET | `/providers` | List all providers |
| POST | `/providers` | Create provider (optional image upload) |
| GET | `/providers/:id` | Get provider by ID |
| PUT | `/providers/:id` | Update provider |
| DELETE | `/providers/:id` | Delete provider + EFS image |
| GET | `/providers/image/:filename` | Serve provider image from EFS |
| GET | `/efs` | List all images on EFS |
| POST | `/efs/upload` | Upload image to EFS |
| GET | `/efs/image/:filename` | Serve image from EFS |
| DELETE | `/efs/:filename` | Delete image from EFS |

### order-service (`/orders`)

| Method | Path | Description |
|---|---|---|
| POST | `/orders/generate` | Generate 10 orders → publish to SQS |
| GET | `/orders` | List orders from DynamoDB |

---

## Health Checks

Each service exposes two endpoints:

- `GET /health` — liveness probe, returns immediately: `{ status: "healthy", service: "<name>" }`
- `GET /health/status` — deep check, tests each AWS resource

| Service | Endpoint | Checks |
|---|---|---|
| product-service | `GET /products/health/status` | DynamoDB, DAX (Scan), S3 (HeadBucket) |
| provider-service | `GET /providers/health/status` | Aurora (`SELECT 1`), EFS (write test) |
| order-service | `GET /orders/health/status` | SQS (GetQueueAttributes), DynamoDB |

---

## Verification & Teardown

- **Verify deployment**: [infra/VERIFICATION.md](infra/VERIFICATION.md)
- **Delete all resources**: [infra/TEARDOWN.md](infra/TEARDOWN.md)

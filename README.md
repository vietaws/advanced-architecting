# Product-Provider Management Application

## Overview

This repository demonstrates a **monolith-to-microservices migration** for an AWS Solutions Architect Pro lab.  
The application runs as independent microservices on **Amazon EKS**, fronted by an **AWS ALB** and a **CloudFront + S3** static frontend.

> **Full implementation guide**: [IMPLEMENTATION.md](IMPLEMENTATION.md) — architecture decisions, phase-by-phase setup, file references, verification, and teardown.

---

## Architecture

### New: Microservices on EKS

```
CloudFront (S3 static frontend)
        │
        ▼
ALB — api.yourdomain.com
  ├── /products*      → product-service   (DynamoDB + DAX + S3)
  ├── /providers*     → provider-service  (RDS Aurora PostgreSQL + EFS)
  └── /orders*        → order-service     (SQS + DynamoDB)

EKS Cluster (namespace: app)
  ├── product-service   — ServiceAccount with IRSA
  ├── provider-service  — ServiceAccount with IRSA (also serves /efs routes)
  └── order-service     — ServiceAccount with IRSA

Shared Infrastructure
  ├── EFS PVC (ReadWriteMany) — mounted by provider-service (serves both /providers and /efs routes)
  └── K8s Secrets per service (DB credentials, AWS config)
```

## Repository Structure

```
architecting-pro/
├── infra/                      # ← Infrastructure setup scripts (start here)
│   ├── README.md               # Step-by-step execution guide
│   ├── 01-cluster.sh           # EKS cluster + Graviton node group
│   ├── 02-addons.sh            # EBS/EFS CSI, ALB Controller, CoreDNS
│   ├── 03-oidc-irsa.sh         # OIDC + IAM roles for IRSA
│   ├── 04-k8s-setup.sh         # Namespace, EFS PVC, Secrets, deploy
│   ├── 05-ecr.sh               # ECR repos + build/push images
│   └── iam/
│       ├── product-service-policy.json
│       ├── order-service-policy.json
│       └── alb-controller-policy.json
├── frontend/                   # ← Static frontend (deploy to S3 + CloudFront)
│   ├── config.js               # ONLY file to edit — set API_URL to ALB endpoint
│   ├── index.html              # SPA shell — loads config.js then app.js
│   ├── app.js                  # All UI logic, reads API_URL from config.js
│   └── style.css               # Styles
├── services/
│   ├── product-service/        # CRUD products via DynamoDB + DAX + S3
│   ├── provider-service/       # CRUD providers via RDS Aurora + EFS; also serves /efs routes
│   └── order-service/          # Order generation + SQS publish + DynamoDB read
├── k8s/
│   ├── 01-namespace.yaml
│   ├── 02-efs-pvc.yaml
│   ├── 06-ingress.yaml
│   ├── product-service/
│   ├── provider-service/
│   └── order-service/
└── README.md
```

---

## Services

### product-service (port 3001)
| Item | Detail |
|---|---|
| Routes | `GET/POST/PUT/DELETE /products`, `GET /products-dax` |
| DynamoDB | `products_table` — Scan, PutItem, GetItem, UpdateItem, DeleteItem |
| DAX | Read-through cache via `amazon-dax-client` |
| S3 | Product image upload/download/delete (pre-signed URLs) |
| IRSA permissions | `dynamodb:Scan/PutItem/GetItem/UpdateItem/DeleteItem`, `dax:GetItem/Scan`, `s3:PutObject/GetObject/DeleteObject` |

### provider-service (port 3002)
| Item | Detail |
|---|---|
| Routes | `GET/POST/PUT/DELETE /providers`, `GET /providers/image/:filename`, `GET /efs`, `POST /efs/upload`, `GET /efs/image/:filename`, `DELETE /efs/:filename` |
| Database | RDS Aurora PostgreSQL — `providers` table in `providers_db` |
| Storage | EFS PVC mount at `/data/efs` for provider images and shared EFS management |
| IRSA permissions | None (RDS accessed via pg driver with K8s Secret credentials; EFS via PVC) |

### order-service (port 3003)
| Item | Detail |
|---|---|
| Routes | `POST /orders/generate`, `GET /orders` |
| SQS | Publishes 10 orders per batch to `orders` queue |
| DynamoDB | `orders_table` — Scan to list orders |
| IRSA permissions | `sqs:SendMessage/GetQueueAttributes`, `dynamodb:Scan` |

---

## Frontend Deployment (S3 + CloudFront)

The frontend is a vanilla JS SPA — four static files, no build step.  
`config.js` is the **only file you ever edit**.

### Frontend-first approach

You can deploy the frontend **before any backend service exists**.  
When `API_URL` is empty the dashboard shows every infrastructure resource as **Disconnected** (red) without making any network calls.  
Once you deploy a backend service, update `API_URL` in `config.js`, re-upload the file, and invalidate CloudFront. The dashboard immediately reflects the real status of each service's AWS resources.

```
Deploy frontend (API_URL = '')  →  All resources: Disconnected
Deploy product-service          →  DynamoDB / DAX / S3 turn Connected
Deploy provider-service         →  Aurora / EFS turn Connected
Deploy order-service            →  SQS turns Connected
```

### Dashboard — infrastructure status cards

The home tab shows one card per service, each listing its AWS resources:

| Card | Resources checked |
|---|---|
| Product Service | DynamoDB, DAX, S3 |
| Provider Service | Aurora (RDS), EFS |
| Order Service | SQS |

Status is fetched from each service's `GET /health/status` endpoint on page load or when you click **↻ Refresh**.

### 1. Configure the API endpoint

Edit `frontend/config.js`:

```js
window.APP_CONFIG = {
  // Set to your ALB endpoint once the backend is deployed.
  // Leave empty to run frontend-only (all resources show as Disconnected).
  API_URL: '',
};
```

When the backend is ready:
```js
window.APP_CONFIG = {
  API_URL: 'https://api.yourdomain.com',  // ALB DNS or custom domain — no trailing slash
};
```

### 2. Create S3 bucket

```bash
FRONTEND_BUCKET="demo-frontend-$(openssl rand -hex 4)"

aws s3api create-bucket \
  --bucket "$FRONTEND_BUCKET" \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1

# Block all public access — CloudFront OAC serves the files
aws s3api put-public-access-block \
  --bucket "$FRONTEND_BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

### 3. Upload files

```bash
aws s3 sync frontend/ s3://$FRONTEND_BUCKET --delete
```

### 4. Create CloudFront distribution

```bash
aws cloudfront create-distribution \
  --origin-domain-name "${FRONTEND_BUCKET}.s3.ap-southeast-1.amazonaws.com" \
  --default-root-object index.html
```

> Use Origin Access Control (OAC) to allow CloudFront to access the private S3 bucket without making it public.

### 5. Activate backend (after EKS services are deployed)

```bash
# Edit config.js — set API_URL to your ALB endpoint
vi frontend/config.js

# Re-upload only config.js
aws s3 cp frontend/config.js s3://$FRONTEND_BUCKET/config.js

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id YOUR_DISTRIBUTION_ID \
  --paths "/config.js"
```

---

## Infrastructure Setup

> **Full setup guide**: [`infra/README.md`](infra/README.md)

Run scripts in order:

```bash
chmod +x infra/*.sh
export AWS_ACCOUNT_ID="123456789012"

./infra/01-cluster.sh    # EKS cluster + Graviton node group
./infra/02-addons.sh     # EBS/EFS CSI, ALB Controller
./infra/03-oidc-irsa.sh  # IRSA roles for product-service + order-service
./infra/05-ecr.sh        # Build & push Docker images to ECR
./infra/04-k8s-setup.sh  # Namespace, Secrets, deploy all services
```

- EKS cluster with AWS Load Balancer Controller installed
- EFS CSI Driver installed on EKS
- IAM OIDC provider configured for IRSA
- VPC with subnets tagged for ALB

#### VPC Layout
| Subnet | CIDR |
|---|---|
| public-1, public-2 | `10.1.1.0/24`, `10.1.2.0/24` |
| app-1, app-2 | `10.1.3.0/24`, `10.1.4.0/24` |
| db-1, db-2 | `10.1.5.0/24`, `10.1.6.0/24` |


> For complete step-by-step instructions — AWS resource creation, IRSA setup, K8s secrets, Docker builds, and teardown — see **[IMPLEMENTATION.md](IMPLEMENTATION.md)**.

---

## API Endpoints

### product-service (`/products`)
| Method | Path | Description |
|---|---|---|
| GET | `/products` | List all products (DynamoDB) |
| GET | `/products-dax` | List all products (DAX cache) |
| POST | `/products` | Create product (with optional image upload) |
| PUT | `/products/:id` | Update product |
| DELETE | `/products/:id` | Delete product + S3 image |

### provider-service (`/providers` + `/efs`)
| Method | Path | Description |
|---|---|---|
| GET | `/providers` | List all providers |
| POST | `/providers` | Create provider (with optional image upload) |
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

Each service exposes:
- `GET /health` — liveness probe (returns `{ status: "healthy", service: "<name>" }`)
- `GET /health/status` — deep connectivity check per service

| Service | Endpoint | Checks |
|---|---|---|
| product-service | `GET /products/health/status` | DynamoDB (`products_table`), DAX (Scan Limit 1), S3 (HeadBucket) |
| provider-service | `GET /providers/health/status` | Aurora PostgreSQL (`SELECT 1`), EFS (write access on `/data/efs`) |
| order-service | `GET /orders/health/status` | SQS (GetQueueAttributes), DynamoDB (`orders_table`) |

The frontend dashboard calls all three endpoints in parallel on page load or manual refresh, and renders the results into the service-grouped infrastructure status cards on the home tab.


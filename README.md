# Architecting Pro — Microservices on EKS

A **monolith-to-microservices migration** demo for the AWS Solutions Architect Pro lab.  
Three Node.js services run on **Amazon EKS**, fronted by an **AWS ALB** and a **CloudFront + S3** static frontend.

---

## Architecture

![hello@viet.vn](./images/architecture.png)

```

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
├── guides/                        ← step-by-step guides for each phase
│   ├── phase-0-aws-resources.md
│   ├── phase-1-frontend.md
│   ├── phase-2-eks-cluster.md
│   ├── phase-3-addons.md
│   ├── phase-4-irsa.md
│   ├── phase-5-images.md
│   ├── phase-6-deploy.md
│   ├── verification.md
│   └── teardown.md
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
└── infra/                     ← scripts and manifests only
    ├── 01-aws-resources.sh    ← DynamoDB, S3, SQS provisioning
    ├── 02-addons.sh
    ├── 03-oidc-irsa.sh
    ├── 04-k8s-setup.sh
    ├── teardown-eks.sh
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

## Guides

| Guide | Description |
|---|---|
| [Phase 0 — AWS Resources](guides/phase-0-aws-resources.md) | DynamoDB + S3 + SQS via script; DAX, Aurora, EFS manually |
| [Phase 1 — Frontend](guides/phase-1-frontend.md) | S3 + CloudFront, deploy before backend exists |
| [Phase 2 — EKS Cluster](guides/phase-2-eks-cluster.md) | eksctl cluster + VPC + node group |
| [Phase 3 — EKS Add-ons](guides/phase-3-addons.md) | CSI drivers, ALB Controller |
| [Phase 4 — IAM & IRSA](guides/phase-4-irsa.md) | Least-privilege roles per service |
| [Phase 5 — Container Images](guides/phase-5-images.md) | Build & push to Docker Hub + ECR |
| [Phase 6 — Kubernetes Deploy](guides/phase-6-deploy.md) | Namespace, secrets, deployments, ingress |
| [Verification](guides/verification.md) | Post-deploy checklist |
| [Teardown](guides/teardown.md) | Delete all resources |

---

## Deployment Workflow

> **Frontend-first approach** — Deploy Phase 1 (frontend) before any backend service exists. The dashboard shows all resources as **Disconnected** (red). As you deploy each backend service, the corresponding cards turn **Connected** without any frontend redeployment.

### Phase 0 — AWS Resources

Create all AWS-managed resources before provisioning EKS. Services depend on these at startup.

| Resource | Used by | How |
|---|---|---|
| DynamoDB `products_table` | product-service | `infra/01-aws-resources.sh` |
| DynamoDB `orders_table` | order-service | `infra/01-aws-resources.sh` |
| S3 bucket (product images) | product-service | `infra/01-aws-resources.sh` |
| SQS queue `orders` | order-service | `infra/01-aws-resources.sh` |
| DAX cluster `dax-demo` | product-service | Manual (requires EKS VPC) |
| RDS Aurora PostgreSQL `providers_db` | provider-service | Manual (requires EKS VPC) |
| EFS file system | provider-service | Manual (requires EKS VPC) |

→ **[Full guide: guides/phase-0-aws-resources.md](guides/phase-0-aws-resources.md)**

---

### Phase 1 — Frontend *(deploy first)*

Deploy the static SPA to S3 + CloudFront with `API_URL` left empty. All dashboard cards show **Disconnected** — no backend needed. Once the backend is deployed, set `API_URL` to the ALB endpoint and re-upload `config.js`.

→ **[Full steps: guides/phase-1-frontend.md](guides/phase-1-frontend.md)**

---

### Phase 2 — EKS Cluster

Create the EKS control plane with a new VPC (`10.2.0.0/16`), IAM OIDC provider, and a Graviton Spot node group. Choose between a public node group (no NAT cost) or private (with NAT Gateway).

→ **[Full commands: guides/phase-2-eks-cluster.md](guides/phase-2-eks-cluster.md)**

---

### Phase 3 — EKS Add-ons

Install EBS CSI, EFS CSI, CoreDNS, kube-proxy, and the AWS Load Balancer Controller.

→ **[Detail: guides/phase-3-addons.md](guides/phase-3-addons.md)**

---

### Phase 4 — IAM & IRSA

Create least-privilege IAM roles for `product-service` (DynamoDB, DAX, S3) and `order-service` (SQS, DynamoDB). `provider-service` needs no IRSA — RDS via K8s Secret, EFS via PVC.

→ **[Detail: guides/phase-4-irsa.md](guides/phase-4-irsa.md)**

---

### Phase 5 — Container Images

Build multi-platform images (`linux/amd64,linux/arm64`) locally and push to Docker Hub and/or ECR.

→ **[Build & push guide: guides/phase-5-images.md](guides/phase-5-images.md)**

---

### Phase 6 — Kubernetes Deploy

Apply namespace, EFS PVC, ServiceAccounts, Deployments, Services, and ALB Ingress using environment variables collected from Phases 0–5. After services are running, update `frontend/config.js` with the ALB endpoint.

→ **[Detail: guides/phase-6-deploy.md](guides/phase-6-deploy.md)**

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

- **Verify deployment**: [guides/verification.md](guides/verification.md)
- **Delete all resources**: [guides/teardown.md](guides/teardown.md)

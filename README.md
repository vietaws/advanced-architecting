# AWS Architecting Pro — Containerization on Amazon EKS

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
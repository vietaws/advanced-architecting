# Product-Provider Management Application

## Overview

This repository demonstrates a **monolith-to-microservices migration** for an AWS Solutions Architect Pro lab.  
The original monolith (Node.js on EC2) is preserved in the repo root. The new architecture runs as independent microservices on **Amazon EKS**, fronted by an **AWS ALB** and a **CloudFront + S3** static frontend.

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
├── services/
│   ├── product-service/        # CRUD products via DynamoDB + DAX + S3
│   ├── provider-service/       # CRUD providers via RDS Aurora + EFS; also serves /efs routes
│   └── order-service/          # Order generation + SQS publish + DynamoDB read
├── k8s/
│   ├── namespace.yaml
│   ├── efs-pvc.yaml
│   ├── ingress.yaml
│   ├── product-service/
│   ├── provider-service/
│   └── order-service/
├── public/                     # Legacy frontend (monolith)
├── routes/                     # Legacy route handlers (monolith)
├── db/                         # Legacy DB clients (monolith)
├── server.js                   # Legacy monolith entry point
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

---

### 1. AWS Resources

#### DynamoDB Tables
```bash
# Products table
aws dynamodb create-table \
  --table-name products_table \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-southeast-1

# Orders table
aws dynamodb create-table \
  --table-name orders_table \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-southeast-1
```

#### S3 Bucket (product images)
```bash
# Linux / macOS
aws s3api create-bucket \
  --bucket "demo-product-images-$(openssl rand -hex 4)" \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1
```

#### SQS Queue
```bash
aws sqs create-queue \
  --queue-name orders \
  --attributes '{"VisibilityTimeout":"180"}' \
  --region ap-southeast-1
```

#### DAX Cluster
```bash
# Create DAX subnet group first
aws dax create-subnet-group \
  --subnet-group-name dax-subnet-group \
  --subnet-ids subnet-app1 subnet-app2

# Create DAX cluster
aws dax create-cluster \
  --cluster-name dax-demo \
  --node-type dax.r4.large \
  --replication-factor 1 \
  --iam-role-arn arn:aws:iam::AWS_ACCOUNT_ID:role/DAXRole \
  --subnet-group dax-subnet-group \
  --region ap-southeast-1
```

#### RDS Aurora PostgreSQL
```bash
aws rds create-db-subnet-group \
  --db-subnet-group-name demo-aurora-subnet-group \
  --db-subnet-group-description "Architecting Pro subnet group" \
  --subnet-ids subnet-db1 subnet-db2

aws rds create-db-cluster \
  --db-cluster-identifier demo-aurora-cluster \
  --engine aurora-postgresql \
  --engine-version 16.2 \
  --master-username dbadmin \
  --master-user-password DemoPassword \
  --db-subnet-group-name demo-aurora-subnet-group \
  --vpc-security-group-ids sg-xxx \
  --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=1 \
  --database-name providers_db \
  --no-deletion-protection \
  --region ap-southeast-1

aws rds create-db-instance \
  --db-instance-identifier demo-aurora-instance \
  --db-cluster-identifier demo-aurora-cluster \
  --db-instance-class db.serverless \
  --engine aurora-postgresql \
  --no-publicly-accessible \
  --region ap-southeast-1
```

#### Database Schema
```sql
CREATE TABLE IF NOT EXISTS providers (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  city VARCHAR(100),
  image_filename VARCHAR(255)
);

INSERT INTO providers (name, city) VALUES
  ('Viet AWS', 'Ho Chi Minh City'),
  ('Miracle Tech', 'Hanoi'),
  ('One Training', 'Da Nang');
```

---

### 2. IRSA Setup

Replace `AWS_ACCOUNT_ID`, `OIDC_ID`, and `AWS_REGION` with your values.

#### product-service IAM Policy
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DynamoDBProducts",
      "Effect": "Allow",
      "Action": [
        "dynamodb:Scan",
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:ap-southeast-1:AWS_ACCOUNT_ID:table/products_table"
    },
    {
      "Sid": "DAXProducts",
      "Effect": "Allow",
      "Action": ["dax:GetItem", "dax:Scan"],
      "Resource": "arn:aws:dax:ap-southeast-1:AWS_ACCOUNT_ID:cache/dax-demo"
    },
    {
      "Sid": "S3ProductImages",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:HeadBucket"],
      "Resource": "arn:aws:s3:::YOUR_BUCKET_NAME/products/*"
    }
  ]
}
```

#### order-service IAM Policy
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SQSOrders",
      "Effect": "Allow",
      "Action": ["sqs:SendMessage", "sqs:GetQueueAttributes"],
      "Resource": "arn:aws:sqs:ap-southeast-1:AWS_ACCOUNT_ID:orders"
    },
    {
      "Sid": "DynamoDBOrders",
      "Effect": "Allow",
      "Action": ["dynamodb:Scan"],
      "Resource": "arn:aws:dynamodb:ap-southeast-1:AWS_ACCOUNT_ID:table/orders_table"
    }
  ]
}
```

#### Create IAM Roles for IRSA
```bash
# product-service
aws iam create-role \
  --role-name eks-product-service-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::AWS_ACCOUNT_ID:oidc-provider/oidc.eks.AWS_REGION.amazonaws.com/id/OIDC_ID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.AWS_REGION.amazonaws.com/id/OIDC_ID:sub": "system:serviceaccount:app:product-service-sa",
          "oidc.eks.AWS_REGION.amazonaws.com/id/OIDC_ID:aud": "sts.amazonaws.com"
        }
      }
    }]
  }'

# Attach the policy (after creating it)
aws iam attach-role-policy \
  --role-name eks-product-service-role \
  --policy-arn arn:aws:iam::AWS_ACCOUNT_ID:policy/ProductServicePolicy

# Repeat for order-service with eks-order-service-role + OrderServicePolicy
```

---

### 3. K8s Secrets

```bash
# product-service
kubectl create secret generic product-service-secret \
  --namespace app \
  --from-literal=AWS_REGION=ap-southeast-1 \
  --from-literal=DYNAMODB_PRODUCTS_TABLE=products_table \
  --from-literal=DAX_ENDPOINT=daxs://your-dax-cluster.dax-clusters.ap-southeast-1.amazonaws.com \
  --from-literal=S3_BUCKET=demo-product-images-xxxx

# provider-service
kubectl create secret generic provider-service-secret \
  --namespace app \
  --from-literal=AWS_REGION=ap-southeast-1 \
  --from-literal=RDS_HOST=your-aurora-endpoint.rds.amazonaws.com \
  --from-literal=RDS_PORT=5432 \
  --from-literal=RDS_DATABASE=providers_db \
  --from-literal=RDS_USER=dbadmin \
  --from-literal=RDS_PASSWORD=DemoPassword

# order-service
kubectl create secret generic order-service-secret \
  --namespace app \
  --from-literal=AWS_REGION=ap-southeast-1 \
  --from-literal=DYNAMODB_ORDERS_TABLE=orders_table \
  --from-literal=SQS_QUEUE_URL=https://sqs.ap-southeast-1.amazonaws.com/AWS_ACCOUNT_ID/orders
```

---

### 4. Deploy to EKS

```bash
# Create namespace
kubectl apply -f k8s/namespace.yaml

# Create EFS PVC
kubectl apply -f k8s/efs-pvc.yaml

# Deploy services
kubectl apply -f k8s/product-service/
kubectl apply -f k8s/provider-service/
kubectl apply -f k8s/order-service/

# Deploy ingress
kubectl apply -f k8s/ingress.yaml

# Verify
kubectl get pods -n app
kubectl get ingress -n app
```

---

### 5. Build & Push Docker Images

```bash
# Set your ECR registry
REGISTRY=AWS_ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com

# Login
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin $REGISTRY

# Build and push each service
for svc in product-service provider-service order-service; do
  docker build -t $REGISTRY/$svc:latest ./services/$svc
  docker push $REGISTRY/$svc:latest
done
```

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

The frontend dashboard calls all three endpoints in parallel and merges the results into the service status cards.

---

## Legacy Monolith (EC2)

The original monolith files are preserved in the repo root for reference:
- `server.js`, `routes/`, `db/`, `public/`, `userdata.sh`

See the original setup instructions below for EC2 deployment.

<details>
<summary>Legacy EC2 Setup Instructions</summary>

### EC2 Prerequisites
- VPC: `lab-vpc` (`10.1.0.0/16`)
- Security groups: `public-sg`, `elb-sg`, `app-sg`, `db-sg`
- NACL: allow all inbound/outbound

### Application Deployment
```bash
npm install
npm start
```
Access at: `http://<EC2-Public-IP>:3001`

### Auto Scaling
- Launch Template: AMI with Node.js + app code, IAM role, user data
- ASG: Min 2 / Max 10 / Desired 2, CPU 70% target tracking
- ALB target group on port 3001, health check `/health`

</details>

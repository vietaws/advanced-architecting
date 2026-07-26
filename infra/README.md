# Infrastructure Setup Guide

This folder contains all scripts to provision the EKS cluster and deploy microservices from scratch.

---

## Overview

| Script | What it does |
|---|---|
| `01-cluster.sh` | EKS cluster + Graviton node group + OIDC provider |
| `02-addons.sh` | EBS CSI, EFS CSI, CoreDNS, kube-proxy, AWS Load Balancer Controller |
| `03-oidc-irsa.sh` | IAM policies + roles for IRSA (product-service, order-service) |
| `04-k8s-setup.sh` | Namespace, EFS PVC, K8s Secrets, deploy all services |
| `05-ecr.sh` | Create ECR repos, build Graviton images, push |
| `iam/` | Least-privilege IAM policy documents |

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| AWS CLI v2 | >= 2.15 | `brew install awscli` |
| eksctl | >= 0.180 | `brew install eksctl` |
| kubectl | >= 1.29 | `brew install kubectl` |
| helm | >= 3.14 | `brew install helm` |
| Docker Desktop | >= 4.28 | https://www.docker.com/products/docker-desktop |

AWS credentials must have permissions to create EKS clusters, IAM roles/policies, ECR repos, and manage VPC resources.

---

## Required Values (fill in before running)

| Variable | Where used | Example |
|---|---|---|
| `AWS_ACCOUNT_ID` | All scripts | `123456789012` |
| `SUBNET_APP_1/2` | `01-cluster.sh` | `subnet-0abc...` |
| `SUBNET_PUB_1/2` | `01-cluster.sh` | `subnet-0def...` |
| `EFS_FILE_SYSTEM_ID` | `04-k8s-setup.sh` | `fs-0123456789abcdef0` |
| `PRODUCT_IMAGES_BUCKET` | `03-oidc-irsa.sh` | `demo-product-images-xxxx` |
| `DAX_ENDPOINT` | `04-k8s-setup.sh` | `daxs://xxx.dax-clusters.ap-southeast-1.amazonaws.com` |
| `RDS_HOST` | `04-k8s-setup.sh` | `demo-aurora.cluster-xxx.ap-southeast-1.rds.amazonaws.com` |
| `RDS_PASSWORD` | `04-k8s-setup.sh` | your Aurora master password |
| `SQS_QUEUE_URL` | `04-k8s-setup.sh` | `https://sqs.ap-southeast-1.amazonaws.com/123456789012/orders` |

---

## Execution Order

Run scripts in order. Each script prints the next step on completion.

```bash
# Make all scripts executable
chmod +x infra/*.sh

# Export your account ID (all scripts will auto-detect if not set)
export AWS_ACCOUNT_ID="123456789012"
```

### Step 1 — EKS Cluster

```bash
# Edit subnet IDs inside the script first
vi infra/01-cluster.sh   # set SUBNET_APP_1/2 and SUBNET_PUB_1/2

./infra/01-cluster.sh
```

Creates:
- EKS cluster `demo-cluster` (K8s 1.30, ap-southeast-1)
- Node group `app-nodes`: **m8g.large Graviton4** Spot (2–6 nodes)
  - Fallback: m7g.large, m6g.large (all Graviton, ARM64)
- Public/private subnets tagged for ALB
- IAM OIDC provider for IRSA

### Step 2 — Add-ons

```bash
./infra/02-addons.sh
```

Installs:
- `kube-proxy` and `CoreDNS` (EKS managed)
- `aws-ebs-csi-driver` (EKS managed, with IRSA)
- `aws-efs-csi-driver` (EKS managed, with IRSA)
- `aws-load-balancer-controller` (Helm v1.8.1, with IRSA)

### Step 3 — IRSA Roles

```bash
export PRODUCT_IMAGES_BUCKET="demo-product-images-xxxx"

./infra/03-oidc-irsa.sh
```

Creates IAM policies + roles:

| Role | Service Account | Policy |
|---|---|---|
| `eks-product-service-role` | `product-service-sa` | `ProductServicePolicy` |
| `eks-order-service-role` | `order-service-sa` | `OrderServicePolicy` |

**provider-service** has no IRSA role — it uses K8s Secret for RDS and EFS PVC for storage (no AWS SDK calls requiring IAM).

### Step 4 — Build & Push Images

```bash
# Build linux/arm64 images for Graviton node group
export PRODUCT_IMAGES_BUCKET="demo-product-images-xxxx"

./infra/05-ecr.sh
```

Builds and pushes:
- `product-service:latest` + `:<git-sha>`
- `provider-service:latest` + `:<git-sha>`
- `order-service:latest` + `:<git-sha>`

> **Note**: Images are built for `linux/arm64` (Graviton). If your build machine is x86 without QEMU, set `PLATFORM=linux/amd64` and ensure your node group also uses x86 instances.

### Step 5 — Deploy to EKS

```bash
export EFS_FILE_SYSTEM_ID="fs-0123456789abcdef0"
export DAX_ENDPOINT="daxs://your-cluster.xxxxxx.dax-clusters.ap-southeast-1.amazonaws.com"
export S3_BUCKET="demo-product-images-xxxx"
export RDS_HOST="demo-aurora-cluster.cluster-xxx.ap-southeast-1.rds.amazonaws.com"
export RDS_PASSWORD="YourSecurePassword"
export SQS_QUEUE_URL="https://sqs.ap-southeast-1.amazonaws.com/123456789012/orders"

./infra/04-k8s-setup.sh
```

Applies:
- `k8s/namespace.yaml` — namespace `app`
- `k8s/efs-pvc.yaml` — EFS StorageClass + PV + PVC (shared by provider-service)
- K8s Secrets for all 3 services
- All manifests: ServiceAccounts, Deployments, Services, HPAs
- `k8s/ingress.yaml` — ALB with path-based routing

---

## Node Group Design

| Property | Value | Rationale |
|---|---|---|
| Instance family | m8g / m7g / m6g | Graviton4/3/2 — ARM64, best price/performance |
| Instance size | large (2 vCPU / 8 GB) | Fits all 3 services (2 replicas each, 100m–500m CPU / 128–512 MB) |
| Capacity type | Spot | ~70% cost saving; safe for stateless containers |
| Min / Max | 2 / 6 | Min=2 ensures HA across AZs; HPA scales to 10 pods each |
| Node volume | 20 GB gp3 | Sufficient for container images + OS |
| Subnets | Private (app-1, app-2) | Nodes never have public IPs; ALB sits in public subnets |

**Why not t4g?** The `t` family uses burstable CPU which is unpredictable under load. `m8g` provides consistent baseline CPU — better for demo latency comparisons (DynamoDB vs DAX).

---

## IAM Policies (Least Privilege)

### product-service — `iam/product-service-policy.json`

| Sid | Resource | Actions |
|---|---|---|
| DynamoDBProductsTable | `products_table` | Scan, PutItem, GetItem, UpdateItem, DeleteItem, DescribeTable |
| DAXProductsCluster | `dax-demo` | GetItem, Scan, Query, Put/Update/Delete/BatchGet/BatchWrite |
| S3ProductImagesObjects | `bucket/products/*` | PutObject, GetObject, DeleteObject |
| S3ProductImagesBucket | `bucket` | HeadBucket, ListBucket |

### order-service — `iam/order-service-policy.json`

| Sid | Resource | Actions |
|---|---|---|
| SQSOrdersQueue | `orders` queue | SendMessage, GetQueueAttributes, GetQueueUrl |
| DynamoDBOrdersTable | `orders_table` | Scan, DescribeTable |

### provider-service

No IRSA. Accesses:
- RDS via pg driver (credentials in K8s Secret)
- EFS via PVC mount (no AWS API calls)

---

## Verification

```bash
# Cluster
kubectl get nodes -o wide

# Pods — should all be Running
kubectl get pods -n app

# Ingress — ALB address takes ~2 min to provision
kubectl get ingress -n app

# Test health endpoints
ALB=$(kubectl get ingress app-ingress -n app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$ALB/products/health/status
curl http://$ALB/providers/health/status
curl http://$ALB/orders/health/status
```

---

## Teardown

```bash
# Delete K8s resources
kubectl delete namespace app
kubectl delete -f k8s/efs-pvc.yaml

# Delete cluster (also removes node group and OIDC provider)
eksctl delete cluster --name demo-cluster --region ap-southeast-1

# Delete IAM roles and policies
aws iam detach-role-policy --role-name eks-product-service-role \
  --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ProductServicePolicy
aws iam delete-role --role-name eks-product-service-role

aws iam detach-role-policy --role-name eks-order-service-role \
  --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/OrderServicePolicy
aws iam delete-role --role-name eks-order-service-role

aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ProductServicePolicy
aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/OrderServicePolicy
aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy
```

# Phases 1–5 — EKS Cluster Setup & Deploy

This guide covers everything from provisioning the EKS cluster to deploying all three microservices.

> **Prerequisites**: Complete [Phase 0 — AWS Resources](../aws-resources/README.md) first.  
> **Back to main guide**: [README.md](../../README.md)

---

## Required tools

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

```bash
# Verify AWS credentials
aws sts get-caller-identity
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
```

---

## Phase 1 — EKS Cluster

### Create cluster + VPC + OIDC

One command creates the control plane, a new VPC (`10.2.0.0/16`), public + private subnets across 2 AZs, subnet tags for ALB, and the IAM OIDC provider for IRSA.

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

**Duration:** ~10 minutes. kubeconfig is updated automatically.

### VPC layout (auto-created)

| Subnet type | AZs | Auto-tagged for |
|---|---|---|
| Public (2) | a, b | `kubernetes.io/role/elb=1` (ALB) |
| Private (2) | a, b | `kubernetes.io/role/internal-elb=1` (internal ALB) |

### Create node group

Choose **one** option. You can add the other later.

**Option A — Public nodes** (default, no NAT Gateway cost):

```bash
eksctl create nodegroup \
  --cluster demo-cluster \
  --region ap-southeast-1 \
  --name public-nodes \
  --node-type t4g.medium \
  --spot \
  --nodes 2 --nodes-min 2 --nodes-max 4 \
  --node-volume-size 20 --node-volume-type gp3 \
  --node-zones ap-southeast-1a,ap-southeast-1b \
  --node-labels "role=app,arch=graviton,subnet=public" \
  --managed
```

**Option B — Private nodes** (NAT Gateway, ~$0.045/hr per AZ):

```bash
eksctl create nodegroup \
  --cluster demo-cluster \
  --region ap-southeast-1 \
  --name private-nodes \
  --node-type t4g.medium \
  --spot \
  --nodes 2 --nodes-min 2 --nodes-max 4 \
  --node-volume-size 20 --node-volume-type gp3 \
  --node-zones ap-southeast-1a,ap-southeast-1b \
  --node-private-networking \
  --node-labels "role=app,arch=graviton,subnet=private" \
  --managed
```

**Duration:** ~5 minutes.

### Node group spec

| Property | Value | Notes |
|---|---|---|
| Instance type | t4g.medium | Graviton2, 2 vCPU / 4 GB |
| Capacity | Spot | ~70% cost saving; pods are stateless |
| Min / Desired / Max | 2 / 2 / 4 | HA by default; scales to 4 under load |
| Volume | 20 GB gp3 | Container images + OS |

For production, switch to `m7g.large` or `m8g.large`.

### Verify

```bash
kubectl get nodes -o wide
# Expect 2 nodes, STATUS=Ready, linux/arm64 architecture
```

---

## Phase 2 — EKS Add-ons

**Script:** `02-addons.sh`

```bash
chmod +x infra/eks-cluster/*.sh
./infra/eks-cluster/02-addons.sh
```

Installs:

| Add-on | Method | IRSA role |
|---|---|---|
| kube-proxy | EKS managed | — |
| CoreDNS | EKS managed | — |
| aws-ebs-csi-driver | EKS managed | `AmazonEBSCSIDriverPolicy` |
| aws-efs-csi-driver | EKS managed | `AmazonEFSCSIDriverPolicy` |
| aws-load-balancer-controller | Helm v1.8.1 | `iam/alb-controller-policy.json` |

### Verify

```bash
kubectl get pods -n kube-system | grep -E "coredns|ebs-csi|efs-csi|aws-load-balancer"
# All pods should be Running
```

---

## Phase 3 — IAM & IRSA

**Script:** `03-oidc-irsa.sh`

IRSA lets each pod assume a least-privilege IAM role without static credentials.

```bash
export PRODUCT_IMAGES_BUCKET="demo-product-images-xxxx"   # from Phase 0 Step 2

./infra/eks-cluster/03-oidc-irsa.sh
```

### What it creates

| IAM Role | K8s ServiceAccount | IAM Policy | Permissions |
|---|---|---|---|
| `eks-product-service-role` | `product-service-sa` | `ProductServicePolicy` | DynamoDB (products), DAX, S3 |
| `eks-order-service-role` | `order-service-sa` | `OrderServicePolicy` | SQS (orders), DynamoDB (orders) |

`provider-service` has no IRSA role — it accesses RDS via K8s Secret credentials and EFS via PVC.

### How IRSA works

```
Pod starts
  └── K8s injects signed OIDC token
        └── AWS SDK calls sts:AssumeRoleWithWebIdentity
              └── IAM validates: correct OIDC issuer + namespace:serviceaccount
                    └── Returns temporary credentials
```

### Policy details

**ProductServicePolicy** (`iam/product-service-policy.json`):

| Sid | Resource | Actions |
|---|---|---|
| DynamoDBProductsTable | `products_table` | Scan, PutItem, GetItem, UpdateItem, DeleteItem, DescribeTable |
| DAXProductsCluster | `dax-demo` | GetItem, Scan, Query, BatchGet/Write, Put/Update/Delete |
| S3ProductImagesObjects | `bucket/products/*` | PutObject, GetObject, DeleteObject |
| S3ProductImagesBucket | `bucket` | HeadBucket, ListBucket |

**OrderServicePolicy** (`iam/order-service-policy.json`):

| Sid | Resource | Actions |
|---|---|---|
| SQSOrdersQueue | `orders` queue | SendMessage, GetQueueAttributes, GetQueueUrl |
| DynamoDBOrdersTable | `orders_table` | Scan, DescribeTable |

### Verify

```bash
aws iam get-role --role-name eks-product-service-role \
  --query 'Role.AssumeRolePolicyDocument' --output json
aws iam list-attached-role-policies --role-name eks-product-service-role
```

---

## Phase 4 — Container Images

Build and push images from your local machine before deploying to EKS.  
See **[IMAGES.md](../IMAGES.md)** for complete buildx commands.

### Create ECR repositories (one-time)

```bash
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

### Update deployment manifests

Edit `k8s/*/05-deployment.yaml` — set the `image:` field to your registry before Phase 5.

- **ECR**: `AWS_ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/product-service:latest`
- **Docker Hub**: `vietaws/architecting-pro:product-service-latest`

The `04-k8s-setup.sh` script substitutes the `AWS_ACCOUNT_ID` placeholder automatically for ECR images.

---

## Phase 5 — Kubernetes Deploy

**Script:** `04-k8s-setup.sh`

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export EFS_FILE_SYSTEM_ID="fs-0123456789abcdef0"         # from Phase 0 Step 6
export DAX_ENDPOINT="daxs://xxx.dax-clusters.ap-southeast-1.amazonaws.com:8111"  # Phase 0 Step 4
export S3_BUCKET="demo-product-images-xxxx"              # from Phase 0 Step 2
export RDS_HOST="demo-aurora-cluster.cluster-xxx.ap-southeast-1.rds.amazonaws.com"  # Phase 0 Step 5
export RDS_PASSWORD="YourSecurePassword"
export SQS_QUEUE_URL="https://sqs.ap-southeast-1.amazonaws.com/${AWS_ACCOUNT_ID}/orders"

./infra/eks-cluster/04-k8s-setup.sh
```

### What it applies

| Manifest | Creates |
|---|---|
| `k8s/01-namespace.yaml` | Namespace `app` |
| `k8s/02-efs-pvc.yaml` | StorageClass + PV + PVC (`efs-claim`) |
| `k8s/*/03-serviceaccount.yaml` | 3 ServiceAccounts (2 with IRSA annotations) |
| `k8s/*/05-deployment.yaml` | 3 Deployments, 2 replicas each |
| `k8s/*/04-service.yaml` | 3 ClusterIP Services |
| `k8s/06-ingress.yaml` | ALB Ingress — path-based routing |

### K8s Secrets created

| Secret | Consumed by | Keys |
|---|---|---|
| `product-service-secret` | product-service deployment | `AWS_REGION`, `DYNAMODB_PRODUCTS_TABLE`, `DAX_ENDPOINT`, `S3_BUCKET` |
| `provider-service-secret` | provider-service deployment | `AWS_REGION`, `RDS_HOST`, `RDS_PORT`, `RDS_DATABASE`, `RDS_USER`, `RDS_PASSWORD` |
| `order-service-secret` | order-service deployment | `AWS_REGION`, `DYNAMODB_ORDERS_TABLE`, `SQS_QUEUE_URL` |

All injected via `envFrom.secretRef` — no credentials in manifest files.

### ALB Ingress path routing

| Path prefix | Backend service | Notes |
|---|---|---|
| `/products-dax` | product-service:80 | Listed before `/products` to avoid shadowing |
| `/products` | product-service:80 | |
| `/providers/health` | provider-service:80 | Listed before `/providers` |
| `/providers` | provider-service:80 | |
| `/efs` | provider-service:80 | |
| `/orders` | order-service:80 | |

### Health probes

Each deployment uses `GET /health` for liveness + readiness — returns immediately without checking backends. The deeper `GET /health/status` is for the frontend dashboard only.

### Verify

```bash
# All 6 pods Running
kubectl get pods -n app -o wide

# Get ALB DNS (takes ~2 min to provision)
kubectl get ingress app-ingress -n app
ALB=$(kubectl get ingress app-ingress -n app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Health checks
curl -s http://$ALB/products/health/status | jq .
curl -s http://$ALB/providers/health/status | jq .
curl -s http://$ALB/orders/health/status | jq .
```

---

## Next

→ **[Phase 6 — Frontend](../../README.md#frontend-deployment-s3--cloudfront)**  
→ **[Verification](../VERIFICATION.md)**  
→ **[Teardown](../TEARDOWN.md)**

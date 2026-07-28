# Phase 5 — Kubernetes Deploy

> ← [Back to main guide](../README.md#deployment-workflow)

---

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export EFS_FILE_SYSTEM_ID="fs-0123456789abcdef0"         # Phase 0 Step 6
export DAX_ENDPOINT="daxs://xxx.dax-clusters.ap-southeast-1.amazonaws.com:8111"  # Phase 0 Step 4
export S3_BUCKET="demo-product-images-xxxx"              # Phase 0 Step 2
export RDS_HOST="demo-aurora-cluster.cluster-xxx.ap-southeast-1.rds.amazonaws.com"  # Phase 0 Step 5
export RDS_PASSWORD="YourSecurePassword"
export SQS_QUEUE_URL="https://sqs.ap-southeast-1.amazonaws.com/${AWS_ACCOUNT_ID}/orders"

./infra/eks-cluster/04-k8s-setup.sh
```

---

## What it applies

| Manifest | Creates |
|---|---|
| `infra/eks-cluster/k8s/01-namespace.yaml` | Namespace `app` |
| `infra/eks-cluster/k8s/02-efs-pvc.yaml` | StorageClass + PV + PVC (`efs-claim`) |
| `infra/eks-cluster/k8s/*/03-serviceaccount.yaml` | 3 ServiceAccounts (2 with IRSA annotations) |
| `infra/eks-cluster/k8s/*/05-deployment.yaml` | 3 Deployments, 2 replicas each |
| `infra/eks-cluster/k8s/*/04-service.yaml` | 3 ClusterIP Services |
| `infra/eks-cluster/k8s/06-ingress.yaml` | ALB Ingress — path-based routing |

---

## K8s Secrets

Created by the script, one per service. All injected via `envFrom.secretRef` — no credentials in manifest files.

| Secret | Keys |
|---|---|
| `product-service-secret` | `AWS_REGION`, `DYNAMODB_PRODUCTS_TABLE`, `DAX_ENDPOINT`, `S3_BUCKET` |
| `provider-service-secret` | `AWS_REGION`, `RDS_HOST`, `RDS_PORT`, `RDS_DATABASE`, `RDS_USER`, `RDS_PASSWORD` |
| `order-service-secret` | `AWS_REGION`, `DYNAMODB_ORDERS_TABLE`, `SQS_QUEUE_URL` |

---

## ALB Ingress path routing

| Path prefix | Backend service | Notes |
|---|---|---|
| `/products-dax` | product-service:80 | Before `/products` to avoid prefix shadowing |
| `/products` | product-service:80 | |
| `/providers/health` | provider-service:80 | Before `/providers` |
| `/providers` | provider-service:80 | |
| `/efs` | provider-service:80 | |
| `/orders` | order-service:80 | |

---

## Health probes

Each deployment uses `GET /health` for liveness + readiness — returns immediately without checking backends. The deeper `GET /health/status` is for the frontend dashboard only.

---

## Verify

```bash
# All 6 pods Running
kubectl get pods -n app -o wide

# ALB DNS (takes ~2 min to provision)
kubectl get ingress app-ingress -n app
ALB=$(kubectl get ingress app-ingress -n app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Deep health checks
curl -s http://$ALB/products/health/status  | jq .
curl -s http://$ALB/providers/health/status | jq .
curl -s http://$ALB/orders/health/status    | jq .
```

---

→ Next: [Verification](verification.md)

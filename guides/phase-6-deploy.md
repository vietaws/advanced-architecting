# Phase 6 — Kubernetes Deploy

> ← [Back to main guide](../README.md#deployment-workflow)

---

## Step 1 — Fill in Secret YAML files

All service configuration is managed as Kubernetes Secret YAML files, grouped inside each service folder. Edit each file and replace every `REPLACE_*` placeholder with your real values.

Values for `DAX_ENDPOINT`, `S3_BUCKET`, `SQS_QUEUE_URL` come from the output of `infra/01-aws-resources.sh`.
Values for `RDS_HOST`, `RDS_PASSWORD`, `EFS_FILE_SYSTEM_ID` come from manual steps in [Phase 0](phase-0-aws-resources.md).

**`infra/k8s/product-service/01-secret.yaml`**
```yaml
stringData:
  AWS_REGION: "ap-southeast-1"
  DYNAMODB_PRODUCTS_TABLE: "products_table"
  DAX_ENDPOINT: "daxs://your-dax-endpoint.dax-clusters.ap-southeast-1.amazonaws.com:8111"
  S3_BUCKET: "your-product-images-bucket"
```

**`infra/k8s/provider-service/01-secret.yaml`**
```yaml
stringData:
  AWS_REGION: "ap-southeast-1"
  RDS_HOST: "your-aurora-cluster.cluster-xxx.ap-southeast-1.rds.amazonaws.com"
  RDS_PORT: "5432"
  RDS_DATABASE: "providers_db"
  RDS_USER: "dbadmin"
  RDS_PASSWORD: "your-password"
```

**`infra/k8s/order-service/01-secret.yaml`**
```yaml
stringData:
  AWS_REGION: "ap-southeast-1"
  DYNAMODB_ORDERS_TABLE: "orders_table"
  SQS_QUEUE_URL: "https://sqs.ap-southeast-1.amazonaws.com/ACCOUNT_ID/orders"
```

---

## Step 2 — Run the deploy script

### Option A — Deploy all services at once

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export EFS_FILE_SYSTEM_ID="fs-0123456789abcdef0"   # from Phase 0 Step 6

./infra/04-k8s-setup.sh
```

### Option B — Deploy one service at a time

Use this to bring up services incrementally and verify each one on the frontend dashboard before deploying the next.

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# Product service (DynamoDB + S3 + DAX)
./infra/04-deploy-product.sh

# Provider service (RDS + EFS) — also requires EFS_FILE_SYSTEM_ID
export EFS_FILE_SYSTEM_ID="fs-0123456789abcdef0"
./infra/04-deploy-provider.sh

# Order service (SQS + DynamoDB)
./infra/04-deploy-order.sh
```

> Run `kubectl apply -f infra/k8s/01-namespace.yaml` before deploying individual services if the namespace doesn't exist yet.

After all services are running, apply the ALB Ingress:

```bash
kubectl apply -f infra/k8s/06-ingress.yaml
```

---

## What gets applied

| Manifest | Creates |
|---|---|
| `infra/k8s/01-namespace.yaml` | Namespace `app` |
| `infra/k8s/provider-service/02-efs-pvc.yaml` | StorageClass + PV + PVC (`efs-claim`) |
| `infra/k8s/*/01-secret.yaml` | 3 K8s Secrets (one per service folder) |
| `infra/k8s/*/03-serviceaccount.yaml` | 3 ServiceAccounts (2 with IRSA annotations) |
| `infra/k8s/*/05-deployment.yaml` | 3 Deployments, 2 replicas each |
| `infra/k8s/*/04-service.yaml` | 3 ClusterIP Services |
| `infra/k8s/06-ingress.yaml` | ALB Ingress — path-based routing |

---

## How env vars reach the services

The services read all configuration from `process.env` — there is no `.env` file or dotenv. Kubernetes injects the Secret values as environment variables into each pod at startup via `envFrom.secretRef` in each Deployment manifest.

```
Secret YAML file  →  kubectl apply
  →  K8s Secret stored in etcd
    →  kubelet injects into container env at pod startup
      →  process.env.VARIABLE_NAME in Node.js
```

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

## Restart Deployment

```bash
kubectl rollout restart deployment/product-service -n app

kubectl rollout status deployment/product-service -n app

kubectl rollout restart deployment/product-service deployment/provider-service deployment/order-service -n app

kubectl rollout status deployment/product-service -n app
kubectl rollout status deployment/provider-service -n app
kubectl rollout status deployment/order-service -n app

kubectl get pods -n app -w

kubectl -n app logs deployments/product-service -f --all-pods=true
```

→ Next: [Verification](verification.md)

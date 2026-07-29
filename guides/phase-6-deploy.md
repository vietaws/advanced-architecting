# Phase 6 — Kubernetes Deploy

> ← [Back to main guide](../README.md#deployment-workflow)

---

## Step 1 — Fill in Secret YAML files

All service configuration is managed as Kubernetes Secret YAML files under `eks-setup/k8s/secrets/`. Edit each file and replace every `REPLACE_*` placeholder with your real values collected in Phase 0.

### product-service-secret.yaml

```yaml
stringData:
  AWS_REGION: "ap-southeast-1"
  DYNAMODB_PRODUCTS_TABLE: "products_table"
  DAX_ENDPOINT: "daxs://your-dax-endpoint.dax-clusters.ap-southeast-1.amazonaws.com:8111"
  S3_BUCKET: "your-product-images-bucket"
```

### provider-service-secret.yaml

```yaml
stringData:
  AWS_REGION: "ap-southeast-1"
  RDS_HOST: "your-aurora-cluster.cluster-xxx.ap-southeast-1.rds.amazonaws.com"
  RDS_PORT: "5432"
  RDS_DATABASE: "providers_db"
  RDS_USER: "dbadmin"
  RDS_PASSWORD: "your-password"
```

### order-service-secret.yaml

```yaml
stringData:
  AWS_REGION: "ap-southeast-1"
  DYNAMODB_ORDERS_TABLE: "orders_table"
  SQS_QUEUE_URL: "https://sqs.ap-southeast-1.amazonaws.com/ACCOUNT_ID/orders"
```

---

## Step 2 — Run the deploy script

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export EFS_FILE_SYSTEM_ID="fs-0123456789abcdef0"   # from Phase 0 Step 6

./eks-setup/04-k8s-setup.sh
```

The script fails immediately if any `REPLACE_*` placeholder is still present in the secret files — no partial deployments.

---

## What gets applied

| Manifest | Creates |
|---|---|
| `eks-setup/k8s/01-namespace.yaml` | Namespace `app` |
| `eks-setup/k8s/02-efs-pvc.yaml` | StorageClass + PV + PVC (`efs-claim`) |
| `eks-setup/k8s/secrets/*.yaml` | 3 K8s Secrets (one per service) |
| `eks-setup/k8s/*/03-serviceaccount.yaml` | 3 ServiceAccounts (2 with IRSA annotations) |
| `eks-setup/k8s/*/05-deployment.yaml` | 3 Deployments, 2 replicas each |
| `eks-setup/k8s/*/04-service.yaml` | 3 ClusterIP Services |
| `eks-setup/k8s/06-ingress.yaml` | ALB Ingress — path-based routing |

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

→ Next: [Verification](verification.md)

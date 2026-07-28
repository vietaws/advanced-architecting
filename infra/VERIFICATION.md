# Verification

Full verification checklist after completing all phases.

> **Back to main guide**: [README.md](../README.md)

---

## Cluster

```bash
# Nodes — expect 2 nodes, STATUS=Ready, linux/arm64
kubectl get nodes -o wide

# Add-ons — all pods should be Running
kubectl get pods -n kube-system | grep -E "coredns|ebs-csi|efs-csi|aws-load-balancer"
```

---

## Pods & Services

```bash
# All 6 pods Running (2 per service)
kubectl get pods -n app -o wide

# ClusterIP services
kubectl get svc -n app

# EFS PVC bound
kubectl get pvc -n app
# Expect: efs-claim   Bound   ...   ReadWriteMany
```

---

## Ingress / ALB

```bash
# ALB address — takes ~2 min to provision after first apply
kubectl get ingress app-ingress -n app

# Save ALB hostname
ALB=$(kubectl get ingress app-ingress -n app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB: $ALB"
```

---

## Health endpoints

```bash
# Liveness probes (fast check, no backend calls)
curl -s http://$ALB/products/health  | jq .
curl -s http://$ALB/providers/health | jq .
curl -s http://$ALB/orders/health    | jq .

# Deep connectivity checks (backend + AWS resources)
curl -s http://$ALB/products/health/status  | jq .
curl -s http://$ALB/providers/health/status | jq .
curl -s http://$ALB/orders/health/status    | jq .
```

Expected responses when all resources are connected:

```json
// /products/health/status
{ "dynamodb": { "status": "connected" }, "dax": { "status": "connected" }, "s3": { "status": "connected" } }

// /providers/health/status
{ "aurora": { "status": "connected" }, "efs": { "status": "connected" } }

// /orders/health/status
{ "sqs": { "status": "connected" }, "dynamodb": { "status": "connected" } }
```

---

## API smoke tests

```bash
# Products — DynamoDB
curl -s http://$ALB/products | jq 'length'

# Products — DAX cache
curl -s http://$ALB/products-dax | jq 'length'

# Providers — Aurora
curl -s http://$ALB/providers | jq '.[].name'

# Orders — generate batch to SQS
curl -s -X POST http://$ALB/orders/generate | jq .

# Orders — read from DynamoDB
curl -s http://$ALB/orders | jq 'length'

# EFS — list files
curl -s http://$ALB/efs | jq .
```

---

## IRSA verification

```bash
# Confirm product-service pod has the correct IAM role injected
kubectl exec -n app \
  $(kubectl get pod -n app -l app=product-service -o jsonpath='{.items[0].metadata.name}') \
  -- env | grep AWS_ROLE_ARN
# Expected: AWS_ROLE_ARN=arn:aws:iam::ACCOUNT_ID:role/eks-product-service-role

# Same for order-service
kubectl exec -n app \
  $(kubectl get pod -n app -l app=order-service -o jsonpath='{.items[0].metadata.name}') \
  -- env | grep AWS_ROLE_ARN
# Expected: AWS_ROLE_ARN=arn:aws:iam::ACCOUNT_ID:role/eks-order-service-role
```

---

## Frontend

```bash
# Open the CloudFront URL in a browser
# Home tab → Infrastructure Status cards should show Connected for all deployed services

# If any service shows Disconnected, check:
curl -s http://$ALB/products/health/status | jq .
kubectl logs -n app -l app=product-service --tail=20
```

# Commands


---

## Cluster

```bash
# Nodes — expect 2, STATUS=Ready, linux/arm64
kubectl get nodes -o wide

# Add-ons — all pods Running
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
kubectl get ingress app-ingress -n app

ALB=$(kubectl get ingress app-ingress -n app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB: $ALB"
```

---

## Health endpoints

```bash
# Liveness (fast, no backend calls)
curl -s http://$ALB/products/health  | jq .
curl -s http://$ALB/providers/health | jq .
curl -s http://$ALB/orders/health    | jq .

# Deep connectivity checks
curl -s http://$ALB/products/health/status  | jq .
curl -s http://$ALB/providers/health/status | jq .
curl -s http://$ALB/orders/health/status    | jq .
```

Expected when all resources are connected:

```json
{ "dynamodb": { "status": "connected" }, "dax": { "status": "connected" }, "s3": { "status": "connected" } }
{ "aurora": { "status": "connected" }, "efs": { "status": "connected" } }
{ "sqs": { "status": "connected" }, "dynamodb": { "status": "connected" } }
```

---

## API smoke tests

```bash
curl -s http://$ALB/products      | jq 'length'
curl -s http://$ALB/products-dax  | jq 'length'
curl -s http://$ALB/providers     | jq '.[].name'
curl -s -X POST http://$ALB/orders/generate | jq .
curl -s http://$ALB/orders        | jq 'length'
curl -s http://$ALB/efs           | jq .
```

---

## IRSA

```bash
kubectl exec -n app \
  $(kubectl get pod -n app -l app=product-service -o jsonpath='{.items[0].metadata.name}') \
  -- env | grep AWS_ROLE_ARN
# Expected: arn:aws:iam::ACCOUNT_ID:role/eks-product-service-role

kubectl exec -n app \
  $(kubectl get pod -n app -l app=order-service -o jsonpath='{.items[0].metadata.name}') \
  -- env | grep AWS_ROLE_ARN
# Expected: arn:aws:iam::ACCOUNT_ID:role/eks-order-service-role
```

---

## Frontend

Open the CloudFront URL in a browser. The home tab Infrastructure Status cards should show **Connected** for all deployed services.

If any card shows Disconnected:

```bash
curl -s http://$ALB/products/health/status | jq .
kubectl logs -n app -l app=product-service --tail=20
```

---
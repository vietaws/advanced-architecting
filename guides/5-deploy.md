# Deploy 3 Services on Amazon EKS

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
## Reload deployment when new variables

# Restart Deployment
kubectl rollout restart deployment/product-service -n app
kubectl rollout status deployment/product-service -n app
kubectl rollout status deployment/order-service -n app

kubectl rollout restart deployment/product-service deployment/provider-service deployment/order-service -n app

# Check Deployment Status
kubectl rollout status deployment/product-service -n app
kubectl rollout status deployment/provider-service -n app
kubectl rollout status deployment/order-service -n app

# Check Pod Status - Live
kubectl get pods -n app -w

# Check logs by deployment for Troubleshooting
kubectl -n app logs deployments/product-service -f --all-pods=true


## Solve Order Service Pod is pending
# 1. Pod status and which node (or <none>) it's on
  kubectl get pods -n app -o wide
  
# 2. Why the pod can't be scheduled
  kubectl describe pod -n app -l app=order-service | grep -A 20 "Events:"
  
# 3. Node status and available capacity
  kubectl get nodes -o wide
  
# 4. How much CPU/memory is allocated vs available on each node
  kubectl describe nodes | grep -A 5 "Allocated resources"
  
# 5. Check if cluster autoscaler fired and what it decided
  kubectl logs -n kube-system -l app.kubernetes.io/name=cluster-autoscaler --tail=50
```

# Phase 2 — EKS Add-ons

> ← [Back to main guide](../README.md#deployment-workflow)

---

```bash
chmod +x eks-setup/*.sh
./eks-setup/02-addons.sh
```

---

## What it installs

| Add-on | Method | IRSA role |
|---|---|---|
| kube-proxy | EKS managed | — |
| CoreDNS | EKS managed | — |
| aws-ebs-csi-driver | EKS managed | `AmazonEBSCSIDriverPolicy` |
| aws-efs-csi-driver | EKS managed | `AmazonEFSCSIDriverPolicy` |
| aws-load-balancer-controller | Helm v1.8.1 | `eks-setup/iam/alb-controller-policy.json` |

The ALB Controller policy is scoped with conditions so it only manages resources tagged with `elbv2.k8s.aws/cluster`. Key permissions: ALB lifecycle, EC2 security groups, ACM certificate lookup.

---

## Verify

```bash
kubectl get pods -n kube-system | grep -E "coredns|ebs-csi|efs-csi|aws-load-balancer"
# All pods should be Running
```

---

→ Next: [Phase 4 — IAM & IRSA](phase-4-irsa.md)

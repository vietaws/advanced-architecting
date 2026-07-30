# Phase 3 — EKS Add-ons

> ← [Back to main guide](../README.md#deployment-workflow)

---

```bash
chmod +x eks-setup/*.sh
./eks-setup/02-addons.sh
```

The script installs all add-ons and creates the required IAM roles automatically. No manual IAM steps needed.

---

## What it installs

| Add-on | Method | IAM role created |
|---|---|---|
| kube-proxy | EKS managed | — |
| CoreDNS | EKS managed | — |
| aws-ebs-csi-driver | EKS managed | `eks-ebs-csi-driver-role` |
| aws-efs-csi-driver | EKS managed | `eks-efs-csi-driver-role` |
| aws-load-balancer-controller | Helm | `eks-alb-controller-role` |

- Helm EKS Chart - https://github.com/aws/eks-charts 
- Helm aws-load-balancer-controller - https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller

### IAM roles created by this script

| Role | Policy attached | Used by |
|---|---|---|
| `eks-ebs-csi-driver-role` | `AmazonEBSCSIDriverPolicy` (AWS managed) | EBS CSI driver pods |
| `eks-efs-csi-driver-role` | `AmazonEFSCSIDriverPolicy` (custom, inline) | EFS CSI driver pods |
| `eks-alb-controller-role` | `AWSLoadBalancerControllerIAMPolicy` (from `eks-setup/iam/`) | ALB Controller pods |

Each role is created via `eksctl create iamserviceaccount --role-name <name>` which builds the OIDC trust policy automatically and binds the role to the corresponding K8s ServiceAccount in `kube-system`.

---

## Verify

```bash
# All pods should be Running
kubectl get pods -n kube-system | grep -E "coredns|ebs-csi|efs-csi|aws-load-balancer"

# Confirm IAM roles exist
aws iam get-role --role-name eks-ebs-csi-driver-role --query 'Role.RoleName' --output text
aws iam get-role --role-name eks-efs-csi-driver-role --query 'Role.RoleName' --output text
aws iam get-role --role-name eks-alb-controller-role  --query 'Role.RoleName' --output text
```

---

→ Next: [Phase 4 — IAM & IRSA](phase-4-irsa.md)

## Cleanup Addon Commands (For reference)

```bash
# ── 1. Delete EKS addons ──────────────────────────────────────────────────────
  aws eks delete-addon --cluster-name demo-cluster --addon-name aws-ebs-csi-driver --region ap-southeast-1
  aws eks delete-addon --cluster-name demo-cluster --addon-name aws-efs-csi-driver --region ap-southeast-1
  
  # ── 2. Delete IAM roles ───────────────────────────────────────────────────────
  # EBS role (only one that exists)
  aws iam detach-role-policy \
    --role-name eks-ebs-csi-driver-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
  
  aws iam delete-role --role-name eks-ebs-csi-driver-role

  # ── 3. EFS CSI role ──────────────────────────────────────────────────────────────
  aws iam detach-role-policy \
    --role-name eks-efs-csi-driver-role \
    --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AmazonEFSCSIDriverPolicy \
    2>/dev/null && echo "EFS policy detached" || echo "EFS role not found"
  
  aws iam delete-role --role-name eks-efs-csi-driver-role \
    2>/dev/null && echo "EFS role deleted" || echo "EFS role not found"
  
  # ── 4. Delete K8s ServiceAccounts ────────────────────────────────────────────
  kubectl delete serviceaccount ebs-csi-controller-sa -n kube-system --ignore-not-found
  kubectl delete serviceaccount efs-csi-controller-sa -n kube-system --ignore-not-found
  
  # ── 5. Wait for addons to finish deleting (~30 sec), then verify clean ────────
  aws eks list-addons --cluster-name demo-cluster --region ap-southeast-1
  aws iam list-roles --query "Roles[?starts_with(RoleName,'eks-')].RoleName"
  --output text
  
  # ── 6. Uninstall Helm release ───────────────────────
  helm uninstall aws-load-balancer-controller -n kube-system
  kubectl delete serviceaccount aws-load-balancer-controller -n kube-system --ignore-not-found

  aws iam detach-role-policy \
    --role-name eks-alb-controller-role \
    --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
    2>/dev/null && echo "Policy detached" || echo "Role not found"
  
  aws iam delete-role --role-name eks-alb-controller-role \
    2>/dev/null && echo "Role deleted" || echo "Role not found"

  aws iam delete-policy \
    --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
    2>/dev/null && echo "Policy deleted" || echo "Policy not found"
  
  # ── 6. Re-run addon script ────────────────────────────────────────────────────
  ./eks-setup/02-addons.sh
```
# Infrastructure

This folder contains all provisioning guides and scripts for the Architecting Pro demo.

> **Main guide**: [README.md](../README.md)

---

## Navigation

| Document | Description |
|---|---|
| [aws-resources/README.md](aws-resources/README.md) | **Phase 0** — Create DynamoDB, S3, SQS, DAX, Aurora, EFS |
| [eks-cluster/README.md](eks-cluster/README.md) | **Phases 1–5** — EKS cluster, add-ons, IRSA, images, K8s deploy |
| [IMAGES.md](IMAGES.md) | Build and push container images to Docker Hub and ECR |
| [VERIFICATION.md](VERIFICATION.md) | Verify all resources and services after deployment |
| [TEARDOWN.md](TEARDOWN.md) | Delete all resources when the lab is complete |

---

## Execution order

```
Phase 0  →  infra/aws-resources/README.md     (DynamoDB, S3, SQS, DAX, Aurora, EFS)
Phase 1  →  infra/eks-cluster/README.md       (EKS cluster + VPC + OIDC)
Phase 2  →  infra/eks-cluster/README.md       (EKS add-ons)
Phase 3  →  infra/eks-cluster/README.md       (IAM + IRSA)
Phase 4  →  infra/IMAGES.md                   (build + push container images)
Phase 5  →  infra/eks-cluster/README.md       (Kubernetes deploy)
Phase 6  →  README.md (root)                  (Frontend: S3 + CloudFront)
```

---

## Folder structure

```
infra/
├── README.md                  ← this file
├── IMAGES.md                  ← container image build & push guide
├── VERIFICATION.md            ← post-deployment verification checklist
├── TEARDOWN.md                ← delete all resources
│
├── aws-resources/
│   └── README.md              ← Phase 0: AWS resource provisioning (CLI commands)
│
└── eks-cluster/
    ├── README.md              ← Phases 1–5: EKS setup and deploy
    ├── 02-addons.sh           ← EBS/EFS CSI drivers, ALB Controller
    ├── 03-oidc-irsa.sh        ← IAM policies and IRSA roles
    ├── 04-k8s-setup.sh        ← Namespace, Secrets, deploy all services
    ├── iam/
    │   ├── product-service-policy.json
    │   ├── order-service-policy.json
    │   └── alb-controller-policy.json
    └── k8s/
        ├── 01-namespace.yaml
        ├── 02-efs-pvc.yaml
        ├── 06-ingress.yaml
        ├── product-service/
        ├── provider-service/
        └── order-service/
```

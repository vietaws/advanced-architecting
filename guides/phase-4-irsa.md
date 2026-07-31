# Phase 3 — IAM & IRSA

> ← [Back to main guide](../README.md#deployment-workflow)

---

IRSA (IAM Roles for Service Accounts) lets each pod assume a least-privilege IAM role without static credentials. The OIDC provider created in Phase 1 bridges K8s service accounts to IAM roles.

```bash
# PRODUCT_IMAGES_BUCKET is printed by infra/01-aws-resources.sh
export PRODUCT_IMAGES_BUCKET="demo-product-images-xxxx"
./infra/03-oidc-irsa.sh
```

---

## How IRSA works

```
Pod starts
  └── K8s injects signed OIDC token
        └── AWS SDK calls sts:AssumeRoleWithWebIdentity
              └── IAM validates: correct OIDC issuer + namespace:serviceaccount
                    └── Returns temporary credentials
```

---

## Roles created

| IAM Role | K8s ServiceAccount | Permissions |
|---|---|---|
| `eks-product-service-role` | `product-service-sa` | DynamoDB (products), DAX, S3 |
| `eks-order-service-role` | `order-service-sa` | SQS (orders), DynamoDB (orders) |

`provider-service` has no IRSA role — it uses a K8s Secret for RDS credentials and a PVC for EFS.

---

## Policy details

**ProductServicePolicy** (`infra/iam/product-service-policy.json`):

| Sid | Resource | Actions |
|---|---|---|
| DynamoDBProductsTable | `products_table` | Scan, PutItem, GetItem, UpdateItem, DeleteItem, DescribeTable |
| DAXProductsCluster | `dax-demo` | GetItem, Scan, Query, BatchGet/Write, Put/Update/Delete |
| S3ProductImagesObjects | `bucket/products/*` | PutObject, GetObject, DeleteObject |
| S3ProductImagesBucket | `bucket` | HeadBucket, ListBucket |

**OrderServicePolicy** (`infra/iam/order-service-policy.json`):

| Sid | Resource | Actions |
|---|---|---|
| SQSOrdersQueue | `orders` queue | SendMessage, GetQueueAttributes, GetQueueUrl |
| DynamoDBOrdersTable | `orders_table` | Scan, DescribeTable |

---

## Verify

```bash
aws iam get-role --role-name eks-product-service-role \
  --query 'Role.AssumeRolePolicyDocument' --output json
aws iam list-attached-role-policies --role-name eks-product-service-role
```

---

→ Next: [Phase 5 — Container Images](phase-5-images.md)

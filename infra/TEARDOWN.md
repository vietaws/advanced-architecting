# Teardown

Delete all resources created during this lab. Run in the order shown — EKS resources first, then AWS resources.

> **Back to main guide**: [README.md](../README.md)

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGION="ap-southeast-1"
```

---

## Step 1 — Kubernetes resources

```bash
# Delete all app workloads
kubectl delete namespace app

# Delete EFS PVC (outside the namespace to avoid orphaned PVs)
kubectl delete -f infra/eks-cluster/k8s/02-efs-pvc.yaml
```

---

## Step 2 — EKS cluster

This also deletes the node groups, OIDC provider, and the VPC created by eksctl.

```bash
eksctl delete cluster --name demo-cluster --region $REGION
```

**Duration:** ~10 minutes.

---

## Step 3 — IAM roles and policies

```bash
# Detach policies and delete roles
for ROLE in eks-product-service-role eks-order-service-role; do
  aws iam list-attached-role-policies --role-name $ROLE \
    --query 'AttachedPolicies[*].PolicyArn' --output text \
  | tr '\t' '\n' \
  | xargs -I {} aws iam detach-role-policy --role-name $ROLE --policy-arn {}
  aws iam delete-role --role-name $ROLE
  echo "✓ Deleted role: $ROLE"
done

# Delete IAM policies
for POLICY in ProductServicePolicy OrderServicePolicy AWSLoadBalancerControllerIAMPolicy AmazonEFSCSIDriverPolicy; do
  ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY}"
  aws iam delete-policy --policy-arn "$ARN" 2>/dev/null \
    && echo "✓ Deleted policy: $POLICY" \
    || echo "  Not found (already deleted): $POLICY"
done
```

---

## Step 4 — ECR repositories

```bash
for REPO in product-service provider-service order-service; do
  aws ecr delete-repository \
    --repository-name $REPO \
    --force \
    --region $REGION \
    && echo "✓ Deleted ECR repo: $REPO"
done
```

---

## Step 5 — AWS resources

### DynamoDB

```bash
aws dynamodb delete-table --table-name products_table --region $REGION
aws dynamodb delete-table --table-name orders_table   --region $REGION
```

### SQS

```bash
# Get queue URL if not already set
SQS_QUEUE_URL=$(aws sqs get-queue-url \
  --queue-name orders --region $REGION \
  --query QueueUrl --output text)

aws sqs delete-queue --queue-url "$SQS_QUEUE_URL" --region $REGION
```

### DAX

```bash
aws dax delete-cluster --cluster-name dax-demo --region $REGION

# Wait until deleted, then remove subnet group
aws dax delete-subnet-group --subnet-group-name dax-subnet-group --region $REGION

# Delete DAX IAM role
aws iam detach-role-policy \
  --role-name DAXRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
aws iam delete-role --role-name DAXRole
```

### RDS Aurora

```bash
aws rds delete-db-instance \
  --db-instance-identifier demo-aurora-instance \
  --skip-final-snapshot \
  --region $REGION

# Wait until instance is deleted, then delete cluster
aws rds delete-db-cluster \
  --db-cluster-identifier demo-aurora-cluster \
  --skip-final-snapshot \
  --region $REGION

# Delete subnet group
aws rds delete-db-subnet-group \
  --db-subnet-group-name demo-aurora-subnet-group \
  --region $REGION
```

### EFS

```bash
# Delete mount targets first (one per AZ)
for MT in $(aws efs describe-mount-targets \
  --file-system-id $EFS_FILE_SYSTEM_ID \
  --query 'MountTargets[*].MountTargetId' --output text \
  --region $REGION); do
  aws efs delete-mount-target --mount-target-id $MT --region $REGION
  echo "✓ Deleted mount target: $MT"
done

# Wait a moment for mount targets to delete, then delete EFS
sleep 30
aws efs delete-file-system \
  --file-system-id $EFS_FILE_SYSTEM_ID \
  --region $REGION
```

### S3 buckets

```bash
# Product images bucket
aws s3 rb s3://$PRODUCT_BUCKET --force

# Frontend bucket
aws s3 rb s3://$FRONTEND_BUCKET --force
```

### CloudFront

```bash
# Disable distribution first, then delete
DIST_ID="YOUR_DISTRIBUTION_ID"

# Get the current ETag
ETAG=$(aws cloudfront get-distribution --id $DIST_ID \
  --query 'ETag' --output text)

# Get config, set Enabled=false, update
aws cloudfront get-distribution-config --id $DIST_ID \
  --query 'DistributionConfig' > /tmp/cf-config.json
# Edit /tmp/cf-config.json: set "Enabled": false
aws cloudfront update-distribution \
  --id $DIST_ID \
  --if-match $ETAG \
  --distribution-config file:///tmp/cf-config.json

# After status changes to Deployed, delete
NEW_ETAG=$(aws cloudfront get-distribution --id $DIST_ID --query 'ETag' --output text)
aws cloudfront delete-distribution --id $DIST_ID --if-match $NEW_ETAG
```

---

## Verify cleanup

```bash
# EKS
aws eks list-clusters --region $REGION

# ECR
aws ecr describe-repositories --region $REGION

# DynamoDB
aws dynamodb list-tables --region $REGION

# RDS
aws rds describe-db-clusters --region $REGION

# EFS
aws efs describe-file-systems --region $REGION

# SQS
aws sqs list-queues --region $REGION
```

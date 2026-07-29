# Teardown

Delete all resources when the lab is complete. Run in order — K8s first, then EKS, then AWS resources.

> ← [Back to main guide](../README.md#verification--teardown)

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGION="ap-southeast-1"
```

---

## Step 1 — Kubernetes resources

```bash
kubectl delete namespace app
kubectl delete -f eks-setup/k8s/provider-service/02-efs-pvc.yaml
```

---

## Step 2 — EKS cluster

Deletes node groups, OIDC provider, and the VPC created by eksctl.

```bash
eksctl delete cluster --name demo-cluster --region $REGION
```

**Duration:** ~10 minutes.

---

## Step 3 — IAM roles and policies

```bash
for ROLE in eks-product-service-role eks-order-service-role; do
  aws iam list-attached-role-policies --role-name $ROLE \
    --query 'AttachedPolicies[*].PolicyArn' --output text \
  | tr '\t' '\n' \
  | xargs -I {} aws iam detach-role-policy --role-name $ROLE --policy-arn {}
  aws iam delete-role --role-name $ROLE
  echo "✓ $ROLE"
done

for POLICY in ProductServicePolicy OrderServicePolicy AWSLoadBalancerControllerIAMPolicy AmazonEFSCSIDriverPolicy; do
  aws iam delete-policy \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY}" 2>/dev/null \
    && echo "✓ $POLICY" || echo "  not found: $POLICY"
done
```

---

## Step 4 — ECR repositories

```bash
for REPO in product-service provider-service order-service; do
  aws ecr delete-repository --repository-name $REPO --force --region $REGION \
    && echo "✓ $REPO"
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
SQS_QUEUE_URL=$(aws sqs get-queue-url --queue-name orders --region $REGION \
  --query QueueUrl --output text)
aws sqs delete-queue --queue-url "$SQS_QUEUE_URL" --region $REGION
```

### DAX

```bash
aws dax delete-cluster --cluster-name dax-demo --region $REGION
# Wait until deleted, then:
aws dax delete-subnet-group --subnet-group-name dax-subnet-group --region $REGION
aws iam detach-role-policy --role-name DAXRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
aws iam delete-role --role-name DAXRole
```

### RDS Aurora

```bash
aws rds delete-db-instance --db-instance-identifier demo-aurora-instance \
  --skip-final-snapshot --region $REGION
# Wait until deleted, then:
aws rds delete-db-cluster --db-cluster-identifier demo-aurora-cluster \
  --skip-final-snapshot --region $REGION
aws rds delete-db-subnet-group --db-subnet-group-name demo-aurora-subnet-group \
  --region $REGION
```

### EFS

```bash
for MT in $(aws efs describe-mount-targets --file-system-id $EFS_FILE_SYSTEM_ID \
  --query 'MountTargets[*].MountTargetId' --output text --region $REGION); do
  aws efs delete-mount-target --mount-target-id $MT --region $REGION
  echo "✓ mount target $MT"
done
sleep 30
aws efs delete-file-system --file-system-id $EFS_FILE_SYSTEM_ID --region $REGION
```

### S3

```bash
aws s3 rb s3://$PRODUCT_BUCKET  --force
aws s3 rb s3://$FRONTEND_BUCKET --force
```

### CloudFront

```bash
DIST_ID="YOUR_DISTRIBUTION_ID"
ETAG=$(aws cloudfront get-distribution --id $DIST_ID --query 'ETag' --output text)
# Disable: get config, set "Enabled": false, update-distribution, then delete
aws cloudfront get-distribution-config --id $DIST_ID \
  --query 'DistributionConfig' > /tmp/cf-config.json
# edit /tmp/cf-config.json — set "Enabled": false
aws cloudfront update-distribution --id $DIST_ID --if-match $ETAG \
  --distribution-config file:///tmp/cf-config.json
# after status → Deployed:
NEW_ETAG=$(aws cloudfront get-distribution --id $DIST_ID --query 'ETag' --output text)
aws cloudfront delete-distribution --id $DIST_ID --if-match $NEW_ETAG
```

---

## Verify cleanup

```bash
aws eks list-clusters           --region $REGION
aws ecr describe-repositories  --region $REGION
aws dynamodb list-tables        --region $REGION
aws rds describe-db-clusters    --region $REGION
aws efs describe-file-systems   --region $REGION
aws sqs list-queues             --region $REGION
```

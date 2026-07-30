# Teardown

Delete all resources when the lab is complete. Run in order — K8s first, then EKS, then AWS resources.

> ← [Back to main guide](../README.md#verification--teardown)

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export AWS_PAGER=""
REGION="ap-southeast-1"
```

---

## Step 1 — Kubernetes app resources

```bash
kubectl delete namespace app --ignore-not-found
kubectl delete -f eks-setup/k8s/provider-service/02-efs-pvc.yaml --ignore-not-found
```

---

## Step 2 — ALB Controller (Helm + CRDs)

```bash
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true

kubectl delete crd ingressclassparams.elbv2.k8s.aws 2>/dev/null || true
kubectl delete crd targetgroupbindings.elbv2.k8s.aws 2>/dev/null || true
```

---

## Step 3 — EKS add-ons

```bash
for ADDON in aws-ebs-csi-driver aws-efs-csi-driver kube-proxy coredns; do
  aws eks delete-addon \
    --cluster-name demo-cluster \
    --addon-name "${ADDON}" \
    --region "${REGION}" 2>/dev/null && echo "✓ ${ADDON}" || echo "  not found: ${ADDON}"
done
```

---

## Step 4 — Addon IAM roles and policies

```bash
# EBS CSI
aws iam detach-role-policy --role-name eks-ebs-csi-driver-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy 2>/dev/null || true
aws iam delete-role --role-name eks-ebs-csi-driver-role 2>/dev/null || true

# EFS CSI
aws iam detach-role-policy --role-name eks-efs-csi-driver-role \
  --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AmazonEFSCSIDriverPolicy 2>/dev/null || true
aws iam delete-role --role-name eks-efs-csi-driver-role 2>/dev/null || true

# ALB Controller
aws iam detach-role-policy --role-name eks-alb-controller-role \
  --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy 2>/dev/null || true
aws iam delete-role --role-name eks-alb-controller-role 2>/dev/null || true

# Policies
for POLICY in AmazonEFSCSIDriverPolicy AWSLoadBalancerControllerIAMPolicy; do
  aws iam delete-policy \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY}" 2>/dev/null \
    && echo "✓ ${POLICY}" || echo "  not found: ${POLICY}"
done
```

---

## Step 5 — CloudFormation stacks (created by eksctl iamserviceaccount)

`eksctl create iamserviceaccount` creates a CloudFormation stack per ServiceAccount. Delete them before deleting the cluster:

```bash
for STACK in $(aws cloudformation list-stacks \
  --region "${REGION}" \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?starts_with(StackName,'eksctl-demo-cluster')].StackName" \
  --output text); do
  aws cloudformation delete-stack --stack-name "${STACK}" --region "${REGION}"
  echo "Deleting stack: ${STACK}"
done

# Wait for all stacks to finish deleting
aws cloudformation wait stack-delete-complete \
  --stack-name eksctl-demo-cluster-addon-iamserviceaccount-kube-system-aws-load-balancer-controller \
  --region "${REGION}" 2>/dev/null || true
```

---

## Step 6 — App service IAM roles and policies

```bash
for ROLE in eks-product-service-role eks-order-service-role; do
  aws iam list-attached-role-policies --role-name $ROLE \
    --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null \
  | tr '\t' '\n' \
  | xargs -I {} aws iam detach-role-policy --role-name $ROLE --policy-arn {}
  aws iam delete-role --role-name $ROLE 2>/dev/null \
    && echo "✓ $ROLE" || echo "  not found: $ROLE"
done

for POLICY in ProductServicePolicy OrderServicePolicy; do
  aws iam delete-policy \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY}" 2>/dev/null \
    && echo "✓ $POLICY" || echo "  not found: $POLICY"
done
```

---

## Step 7 — EKS cluster

Deletes node groups, OIDC provider, and the VPC created by eksctl.

```bash
eksctl delete cluster --name demo-cluster --region $REGION
```

**Duration:** ~10 minutes.

---

## Step 8 — ECR repositories

```bash
for REPO in product-service provider-service order-service; do
  aws ecr delete-repository --repository-name $REPO --force --region $REGION \
    && echo "✓ $REPO" || echo "  not found: $REPO"
done
```

---

## Step 9 — AWS resources

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
aws rds delete-db-subnet-group \
  --db-subnet-group-name demo-aurora-subnet-group --region $REGION
```

### EFS

```bash
for MT in $(aws efs describe-mount-targets \
  --file-system-id $EFS_FILE_SYSTEM_ID \
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
aws cloudfront get-distribution-config --id $DIST_ID \
  --query 'DistributionConfig' > /tmp/cf-config.json
# Edit /tmp/cf-config.json — set "Enabled": false
aws cloudfront update-distribution --id $DIST_ID --if-match $ETAG \
  --distribution-config file:///tmp/cf-config.json
# After status → Deployed:
NEW_ETAG=$(aws cloudfront get-distribution --id $DIST_ID --query 'ETag' --output text)
aws cloudfront delete-distribution --id $DIST_ID --if-match $NEW_ETAG
```

---

## Verify cleanup

```bash
aws eks list-clusters                                     --region $REGION
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?starts_with(StackName,'eksctl')].StackName" \
  --output text                                           --region $REGION
aws ecr describe-repositories                            --region $REGION
aws dynamodb list-tables                                  --region $REGION
aws rds describe-db-clusters                             --region $REGION
aws efs describe-file-systems                            --region $REGION
aws sqs list-queues                                      --region $REGION
```

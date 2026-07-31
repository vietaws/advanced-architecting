# Phase 0 — AWS Resources

Create all AWS-managed resources **before** provisioning the EKS cluster. The microservices depend on these at startup.

> ← [Back to main guide](../README.md#deployment-workflow)

---

## Steps 1–3 — DynamoDB, S3, SQS (automated)

Run the provisioning script. It creates both DynamoDB tables, the S3 bucket, and the SQS queue — and prints the export commands you need for later scripts.

```bash
./infra/01-aws-resources.sh
```

Copy and export the output values:

```bash
export PRODUCT_IMAGES_BUCKET="demo-product-images-xxxx"
export S3_BUCKET="demo-product-images-xxxx"
export SQS_QUEUE_URL="https://sqs.ap-southeast-1.amazonaws.com/ACCOUNT_ID/orders"
export DYNAMODB_PRODUCTS_TABLE="products_table"
export DYNAMODB_ORDERS_TABLE="orders_table"
```

These are used by:
- `infra/03-oidc-irsa.sh` — needs `PRODUCT_IMAGES_BUCKET`
- `infra/04-k8s-setup.sh` — needs `S3_BUCKET`, `SQS_QUEUE_URL`

---

## Values to save

After completing all steps, you need these for Phase 5 (`04-k8s-setup.sh`):

| Variable | Set after |
|---|---|
| `S3_BUCKET` / `PRODUCT_IMAGES_BUCKET` | Step 1–3 script |
| `SQS_QUEUE_URL` | Step 1–3 script |
| `DAX_ENDPOINT` | Step 4 |
| `RDS_HOST`, `RDS_PASSWORD` | Step 5 |
| `EFS_FILE_SYSTEM_ID` | Step 6 |

---

## Step 4 — DAX Cluster

DAX must be in the same VPC as EKS nodes. Run **after** Phase 1 so you can use the EKS private subnets.

```bash
# Get private subnet IDs created by eksctl
aws ec2 describe-subnets \
  --filters "Name=tag:kubernetes.io/role/internal-elb,Values=1" \
            "Name=tag:alpha.eksctl.io/cluster-name,Values=demo-cluster" \
  --query 'Subnets[*].SubnetId' --output text \
  --region ap-southeast-1

# Create DAX subnet group
aws dax create-subnet-group \
  --subnet-group-name dax-subnet-group \
  --subnet-ids subnet-PRIVATE1 subnet-PRIVATE2 \
  --region ap-southeast-1

# Create DAX service role
aws iam create-role \
  --role-name DAXRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "Service": "dax.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }]
  }'
aws iam attach-role-policy \
  --role-name DAXRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

# Create DAX cluster (~10 min)
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
aws dax create-cluster \
  --cluster-name dax-demo \
  --node-type dax.r4.large \
  --replication-factor 1 \
  --iam-role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/DAXRole" \
  --subnet-group dax-subnet-group \
  --region ap-southeast-1

# Wait until AVAILABLE, then save endpoint
aws dax describe-clusters \
  --cluster-names dax-demo \
  --query 'Clusters[0].ClusterDiscoveryEndpoint' \
  --region ap-southeast-1
# DAX_ENDPOINT = daxs://<host>:8111
```

---

## Step 5 — RDS Aurora PostgreSQL

Run **after** Phase 1 to place Aurora in the EKS VPC.

```bash
# Subnet group (reuse EKS private subnets)
aws rds create-db-subnet-group \
  --db-subnet-group-name eks-demo-aurora-subnet-group \
  --db-subnet-group-description "Architecting Pro Aurora - EKS Demo" \
  --subnet-ids subnet-059eb7e2f75671cbc subnet-0804426286defbe94 \
  --region ap-southeast-1

# Aurora Serverless v2 cluster
aws rds create-db-cluster \
  --db-cluster-identifier eks-demo-aurora-cluster \
  --engine aurora-postgresql \
  --engine-version 18.3 \
  --master-username dbadmin \
  --master-user-password DemoPassword \
  --db-subnet-group-name eks-demo-aurora-subnet-group \
  --vpc-security-group-ids sg-04bf7295230492911 \
  --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=1 \
  --database-name providers_db \
  --no-deletion-protection \
  --region ap-southeast-1

# Writer instance
aws rds create-db-instance \
  --db-instance-identifier eks-demo-aurora-instance \
  --db-cluster-identifier eks-demo-aurora-cluster \
  --db-instance-class db.serverless \
  --engine aurora-postgresql \
  --no-publicly-accessible \
  --region ap-southeast-1

# Save endpoint
RDS_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier eks-demo-aurora-cluster \
  --query 'DBClusters[0].Endpoint' --output text \
  --region ap-southeast-1)
echo "RDS_HOST=$RDS_HOST"
```

### Create schema

Connect via AWS Console Query Editor, psql from a bastion, or a pod port-forward:

```sql
CREATE TABLE IF NOT EXISTS providers (
  id             SERIAL PRIMARY KEY,
  name           VARCHAR(255) NOT NULL,
  city           VARCHAR(100),
  image_filename VARCHAR(255)
);

-- Optional seed data
INSERT INTO providers (name, city) VALUES
  ('Viet AWS',     'Ho Chi Minh City'),
  ('Miracle Tech', 'Hanoi'),
  ('One Training', 'Da Nang');
```

---

## Step 6 — EFS File System

```bash
# Create EFS in the EKS VPC
EFS_FILE_SYSTEM_ID=$(aws efs create-file-system \
  --performance-mode generalPurpose \
  --throughput-mode bursting \
  --tags Key=Name,Value=demo-efs Key=project,Value=architecting-pro \
  --region ap-southeast-1 \
  --query 'FileSystemId' --output text)
echo "EFS_FILE_SYSTEM_ID=$EFS_FILE_SYSTEM_ID"   # save this value

# Mount targets in each private subnet
aws efs create-mount-target \
  --file-system-id "$EFS_FILE_SYSTEM_ID" \
  --subnet-id subnet-PRIVATE1 \
  --security-groups sg-YOUR_EKS_NODES_SG \
  --region ap-southeast-1

aws efs create-mount-target \
  --file-system-id "$EFS_FILE_SYSTEM_ID" \
  --subnet-id subnet-PRIVATE2 \
  --security-groups sg-YOUR_EKS_NODES_SG \
  --region ap-southeast-1

# Verify mount targets are available
aws efs describe-mount-targets \
  --file-system-id "$EFS_FILE_SYSTEM_ID" \
  --query 'MountTargets[*].[MountTargetId,LifeCycleState,SubnetId]' \
  --output table --region ap-southeast-1
```

---

## Summary

```bash
# From 01-aws-resources.sh output:
export PRODUCT_IMAGES_BUCKET="demo-product-images-xxxx"
export S3_BUCKET="demo-product-images-xxxx"
export SQS_QUEUE_URL="https://sqs.ap-southeast-1.amazonaws.com/ACCOUNT_ID/orders"
export DYNAMODB_PRODUCTS_TABLE="products_table"
export DYNAMODB_ORDERS_TABLE="orders_table"

# From steps 4-6 (manual):
export DAX_ENDPOINT="daxs://dax-demo.xxxxxx.dax-clusters.ap-southeast-1.amazonaws.com:8111"
export RDS_HOST="demo-aurora-cluster.cluster-xxxx.ap-southeast-1.rds.amazonaws.com"
export RDS_PASSWORD="YourSecurePassword"
export EFS_FILE_SYSTEM_ID="fs-0123456789abcdef0"
```

These are passed to `infra/04-k8s-setup.sh` in Phase 6.

---

→ Next: [Phase 2 — EKS Cluster](phase-2-eks-cluster.md)

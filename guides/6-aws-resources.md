# Aurora Cluster

---

## RDS Aurora PostgreSQL


```bash
# Subnet group (reuse EKS private subnets)
aws rds create-db-subnet-group \
  --db-subnet-group-name eks-demo-aurora-subnet-group \
  --db-subnet-group-description "Architecting Pro Aurora - EKS Demo" \
  --subnet-ids subnet-xxx subnet-yyy \
  --region ap-southeast-1

# Aurora Serverless v2 cluster
aws rds create-db-cluster \
  --db-cluster-identifier eks-demo-aurora-cluster \
  --engine aurora-postgresql \
  --engine-version 18.3 \
  --master-username dbadmin \
  --master-user-password DemoPassword \
  --db-subnet-group-name eks-demo-aurora-subnet-group \
  --vpc-security-group-ids sg-xxx \
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

### Change DAX Cluster Security Group

```bash
aws dax update-cluster \
    --cluster-name dax-demo \
    --security-group-ids SECURITY_GROUP_ID
```


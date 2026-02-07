# DAX (DynamoDB Accelerator) Setup Guide

## Overview
DAX is an in-memory cache for DynamoDB that provides microsecond response times. This application implements DAX caching for the `products_table`.

## Architecture
- **Products Tab**: Direct DynamoDB access (no caching)
- **Products_DAX Tab**: DAX-cached DynamoDB access (faster reads)
- Both tabs use the same `products_table` in DynamoDB

## Setup Instructions

### 1. Create DAX Cluster

**Using AWS Console:**
1. Go to DynamoDB Console → DAX
2. Click **Create cluster**
3. Configure:
   - **Cluster name**: `dax-demo`
   - **Node type**: `dax.t3.small` (or larger for production)
   - **Cluster size**: 1 node (or 3 for HA)
   - **IAM role**: Create new or use existing with DynamoDB access
   - **Subnet group**: Select VPC subnets (same as EC2)
   - **Security group**: Allow port 8111 from EC2 security group
4. Click **Create**

**Using AWS CLI:**
```bash
# Create IAM role for DAX
aws iam create-role \
  --role-name DaxServiceRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "dax.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach DynamoDB access policy
aws iam attach-role-policy \
  --role-name DaxServiceRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

# Create subnet group (use your subnet IDs)
aws dax create-subnet-group \
  --subnet-group-name dax-subnet-group \
  --subnet-ids subnet-xxx subnet-yyy \
  --region us-east-1

# Create DAX cluster
aws dax create-cluster \
  --cluster-name dax-demo \
  --node-type dax.t3.small \
  --replication-factor 1 \
  --iam-role-arn arn:aws:iam::YOUR_ACCOUNT_ID:role/DaxServiceRole \
  --subnet-group-name dax-subnet-group \
  --region us-east-1
```

### 2. Get DAX Endpoint

```bash
# Get cluster endpoint
aws dax describe-clusters \
  --cluster-name dax-demo \
  --query 'Clusters[0].ClusterDiscoveryEndpoint.Address' \
  --output text \
  --region us-east-1
```

Output example: `dax-demo.abc123.dax-clusters.us-east-1.amazonaws.com`

### 3. Update Configuration

Update `app_config.json`:
```json
{
  "dax": {
    "endpoint": "dax-demo.abc123.dax-clusters.us-east-1.amazonaws.com:8111"
  }
}
```

Update `userdata-systemd.sh`:
```bash
DAX_ENDPOINT="dax-demo.abc123.dax-clusters.us-east-1.amazonaws.com:8111"
```

### 4. Configure Security Groups

**DAX Security Group:**
- Inbound: Port 8111 from EC2 security group
- Outbound: All traffic

**EC2 Security Group:**
- Outbound: Port 8111 to DAX security group

```bash
# Add inbound rule to DAX security group
aws ec2 authorize-security-group-ingress \
  --group-id sg-dax-xxx \
  --protocol tcp \
  --port 8111 \
  --source-group sg-ec2-xxx \
  --region us-east-1
```

### 5. Install Dependencies

```bash
npm install amazon-dax-client
```

### 6. Deploy Application

```bash
# Restart application to load DAX client
sudo systemctl restart demo-app
```

## Testing DAX Performance

### Compare Response Times

1. **Products Tab (Direct DynamoDB)**:
   - Click "Products" tab
   - Note response time: `⚡ DynamoDB: XXms` (typically 20-50ms)

2. **Products_DAX Tab (Cached)**:
   - Click "Products_DAX" tab
   - First load: Similar to DynamoDB (cache miss)
   - Subsequent loads: `⚡ DAX: <5ms` (cache hit)

### Performance Test

```bash
# Load Products tab multiple times
for i in {1..10}; do
  curl -s http://<EC2-IP>:3000/products | jq -r '.[0].responseTime'
done

# Load Products_DAX tab multiple times
for i in {1..10}; do
  curl -s http://<EC2-IP>:3000/products-dax | jq -r '.[0].responseTime'
done
```

## Features

### Products Tab (DynamoDB)
- Direct DynamoDB access
- No caching
- Response time: 20-50ms
- Green badge: `⚡ DynamoDB: XXms`

### Products_DAX Tab (DAX)
- DAX-cached access
- In-memory caching
- Response time: <5ms (cache hit)
- Red badge: `⚡ DAX: XXms`

### Operations Supported
- ✅ GET all products (Scan)
- ✅ GET single product (GetItem)
- ✅ POST create product (PutItem)
- ✅ PUT update product (UpdateItem)
- ✅ DELETE product (DeleteItem)

## DAX Caching Behavior

**Cache Hit**: Data found in DAX cache
- Response time: <5ms
- No DynamoDB query

**Cache Miss**: Data not in cache
- Response time: ~20-50ms
- Queries DynamoDB
- Stores result in cache

**Cache TTL**: Default 5 minutes
- Items expire after 5 minutes
- Next access triggers cache refresh

**Write-Through**: Writes go to both DAX and DynamoDB
- Ensures consistency
- Cache updated immediately

## Monitoring

### DAX Metrics (CloudWatch)
- `CPUUtilization`
- `NetworkBytesIn/Out`
- `GetItemRequestCount`
- `QueryRequestCount`
- `ScanRequestCount`
- `ItemCacheHits/Misses`

```bash
# View DAX metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/DAX \
  --metric-name ItemCacheHits \
  --dimensions Name=ClusterName,Value=dax-demo \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 3600 \
  --statistics Sum \
  --region us-east-1
```

## Troubleshooting

**Cannot connect to DAX:**
- Check security group allows port 8111
- Verify EC2 and DAX are in same VPC
- Check DAX cluster status is "available"

**High response times:**
- Check DAX cluster health
- Monitor cache hit ratio
- Consider increasing node size

**Connection timeout:**
```bash
# Test connectivity from EC2
telnet dax-demo.abc123.dax-clusters.us-east-1.amazonaws.com 8111
```

**Check DAX cluster status:**
```bash
aws dax describe-clusters \
  --cluster-name dax-demo \
  --region us-east-1
```

## Cost Optimization

**DAX Pricing:**
- `dax.t3.small`: ~$0.04/hour (~$30/month)
- `dax.r5.large`: ~$0.30/hour (~$220/month)

**When to use DAX:**
- ✅ High read throughput (>1000 reads/sec)
- ✅ Microsecond latency required
- ✅ Read-heavy workloads
- ❌ Write-heavy workloads
- ❌ Low traffic applications

## Cleanup

```bash
# Delete DAX cluster
aws dax delete-cluster \
  --cluster-name dax-demo \
  --region us-east-1

# Delete subnet group
aws dax delete-subnet-group \
  --subnet-group-name dax-subnet-group \
  --region us-east-1
```

Here's how to implement DynamoDB Accelerator (DAX) with your EC2 application:

## Step 1: Create DAX Cluster

bash
# Create DAX subnet group
aws dax create-subnet-group \
  --subnet-group-name my-dax-subnet-group \
  --subnet-ids subnet-xxxxx subnet-yyyyy \
  --description "DAX subnet group"

# Create DAX cluster
aws dax create-cluster \
  --cluster-name my-dax-cluster \
  --node-type dax.t3.small \
  --replication-factor 3 \
  --iam-role-arn arn:aws:iam::ACCOUNT-ID:role/DAXServiceRole \
  --subnet-group-name my-dax-subnet-group \
  --security-group-ids sg-xxxxx


## Step 2: Create IAM Role for DAX

json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "dax.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }]
}


Attach DynamoDB access policy:
json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem"
    ],
    "Resource": "arn:aws:dynamodb:us-east-1:ACCOUNT-ID:table/*"
  }]
}


## Step 3: Configure Security Groups

DAX Security Group:
- Inbound: Port 8111 from EC2 security group
- Outbound: All traffic

bash
aws ec2 authorize-security-group-ingress \
  --group-id sg-dax-xxxxx \
  --protocol tcp \
  --port 8111 \
  --source-group sg-ec2-xxxxx


## Step 4: Update EC2 IAM Role

Add DynamoDB permissions to EC2 instance role:
json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "dynamodb:*",
      "dax:*"
    ],
    "Resource": "*"
  }]
}


## Step 5: Install DAX Client on EC2

### Python

bash
# SSH into EC2
ssh ec2-user@your-ec2-ip

# Install DAX client
pip install amazon-dax-client


### Node.js

bash
npm install amazon-dax-client


## Step 6: Update Application Code

### Python Example

Before (Direct DynamoDB):
python
import boto3

dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
table = dynamodb.Table('my-table')

# Get item
response = table.get_item(Key={'id': '123'})
print(response['Item'])


After (With DAX):
python
from amazondax import AmazonDaxClient

# DAX cluster endpoint
dax_endpoint = 'my-dax-cluster.xxxxx.dax-clusters.us-east-1.amazonaws.com:8111'

# Create DAX client
dax = AmazonDaxClient(endpoint_url=dax_endpoint, region_name='us-east-1')
table = dax.Table('my-table')

# Get item (cached)
response = table.get_item(Key={'id': '123'})
print(response['Item'])


### Node.js Example

Before (Direct DynamoDB):
javascript
const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

const params = {
  TableName: 'my-table',
  Key: { id: '123' }
};

dynamodb.get(params, (err, data) => {
  console.log(data.Item);
});


After (With DAX):
javascript
const AmazonDaxClient = require('amazon-dax-client');

const daxEndpoint = 'my-dax-cluster.xxxxx.dax-clusters.us-east-1.amazonaws.com:8111';
const dax = new AmazonDaxClient({ endpoints: [daxEndpoint], region: 'us-east-1' });

const params = {
  TableName: 'my-table',
  Key: { id: '123' }
};

dax.get(params, (err, data) => {
  console.log(data.Item);
});


## Step 7: Get DAX Cluster Endpoint

bash
# Get cluster endpoint
aws dax describe-clusters \
  --cluster-name my-dax-cluster \
  --query 'Clusters[0].ClusterDiscoveryEndpoint.Address' \
  --output text


## Complete Python Application Example

python
from amazondax import AmazonDaxClient
from flask import Flask, jsonify

app = Flask(__name__)

# Initialize DAX client
dax_endpoint = 'my-dax-cluster.xxxxx.dax-clusters.us-east-1.amazonaws.com:8111'
dax = AmazonDaxClient(endpoint_url=dax_endpoint, region_name='us-east-1')
table = dax.Table('products')

@app.route('/product/<product_id>')
def get_product(product_id):
    response = table.get_item(Key={'id': product_id})
    return jsonify(response.get('Item', {}))

@app.route('/products')
def list_products():
    response = table.scan()
    return jsonify(response.get('Items', []))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000)


## Key Points

1. DAX caches reads - GetItem, Query, Scan operations
2. Writes go through DAX - PutItem, UpdateItem, DeleteItem (write-through cache)
3. Default TTL - 5 minutes for item cache
4. No code changes for basic operations - Just swap the client
5. Same API - DAX client uses same API as DynamoDB

## Performance Improvement

- **Without DAX**: ~10-20ms latency
- **With DAX**: ~1-2ms latency (microseconds for cached items)
- **Best for**: Read-heavy workloads with repeated queries

## Cost Consideration

- DAX cluster runs 24/7
- dax.t3.small: ~$0.04/hour (~$30/month per node)
- Minimum 3 nodes for production: ~$90/month
- Use only if you need sub-millisecond latency

Your application will now use DAX for caching, significantly reducing DynamoDB read latency.

## How Write Operations Work

python
from amazondax import AmazonDaxClient

dax = AmazonDaxClient(endpoint_url='dax-endpoint:8111', region_name='us-east-1')
table = dax.Table('products')

# Write through DAX
table.put_item(Item={'id': '123', 'name': 'Product'})


What happens:
1. Application writes to DAX
2. DAX writes to DynamoDB
3. DAX updates its cache
4. Returns success to application

This is called write-through caching.

## Best Practice: Use DAX for Everything

python
# ✅ CORRECT - Use DAX for all operations
dax_table = dax.Table('products')

# Reads
dax_table.get_item(Key={'id': '123'})
dax_table.query(KeyConditionExpression=...)

# Writes
dax_table.put_item(Item={...})
dax_table.update_item(Key={...}, UpdateExpression=...)
dax_table.delete_item(Key={'id': '123'})


## Don't Mix DAX and DynamoDB Clients

python
# ❌ WRONG - Don't do this
dynamodb = boto3.resource('dynamodb')
dynamodb_table = dynamodb.Table('products')

# Write directly to DynamoDB
dynamodb_table.put_item(Item={'id': '123', 'name': 'Product'})

# Read from DAX
dax_table.get_item(Key={'id': '123'})  # Might return stale data!


Problem: If you write directly to DynamoDB, DAX cache won't be updated, causing stale reads.

## Summary

- **Always use DAX client** for both reads and writes
- DAX handles DynamoDB writes automatically
- Cache stays consistent
- No need to manage two separate clients

## DAX Sizing Best Practices

### Node Type Selection

Based on working set size (frequently accessed data):

| Node Type | Memory | Use Case |
|-----------|--------|----------|
| dax.t3.small | 1.5 GB | Dev/test, small datasets |
| dax.r5.large | 13.5 GB | Production, moderate traffic |
| dax.r5.xlarge | 26.5 GB | High traffic, large working set |
| dax.r5.2xlarge | 52 GB | Very high traffic |

Formula:
Required Memory = Working Set Size × 1.2 (overhead)


Example:
- Frequently accessed data: 10 GB
- Choose: dax.r5.large (13.5 GB)

### Cluster Size (Replication Factor)

| Nodes | Use Case | Availability |
|-------|----------|--------------|
| 1 | Dev/test only | No HA |
| 3 | Production minimum | High availability |
| 10 | Maximum, high traffic | Maximum throughput |

Best practice: Start with 3 nodes for production

### Monitor and Adjust

bash
# Check DAX metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/DAX \
  --metric-name CPUUtilization \
  --dimensions Name=ClusterName,Value=my-dax-cluster \
  --start-time 2026-02-07T00:00:00Z \
  --end-time 2026-02-07T16:00:00Z \
  --period 3600 \
  --statistics Average


Scale up if:
- CPU > 70%
- Memory > 80%
- Cache miss rate > 20%
- Eviction rate is high

## DynamoDB Table Sizing Best Practices

### Capacity Modes

On-Demand (Default recommendation):
bash
aws dynamodb create-table \
  --table-name products \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH


Use when:
- Unpredictable traffic
- New applications
- Spiky workloads
- Don't want to manage capacity

Provisioned (Cost optimization):
bash
aws dynamodb create-table \
  --table-name products \
  --billing-mode PROVISIONED \
  --provisioned-throughput ReadCapacityUnits=100,WriteCapacityUnits=50 \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH


Use when:
- Predictable traffic
- Steady workload
- Cost optimization (can be 50% cheaper)

### Calculate Provisioned Capacity

Read Capacity Units (RCU):
RCU = (Item Size / 4 KB) × Reads per Second


Write Capacity Units (WCU):
WCU = (Item Size / 1 KB) × Writes per Second


Example:
- Item size: 2 KB
- 100 reads/sec, 50 writes/sec
- RCU needed: (2/4) × 100 = 50
- WCU needed: (2/1) × 50 = 100

### Enable Auto Scaling (Provisioned Mode)

bash
aws application-autoscaling register-scalable-target \
  --service-namespace dynamodb \
  --resource-id table/products \
  --scalable-dimension dynamodb:table:ReadCapacityUnits \
  --min-capacity 5 \
  --max-capacity 100

aws application-autoscaling put-scaling-policy \
  --service-namespace dynamodb \
  --resource-id table/products \
  --scalable-dimension dynamodb:table:ReadCapacityUnits \
  --policy-name products-read-scaling \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration \
    TargetValue=70.0,\
    PredefinedMetricSpecification={PredefinedMetricType=DynamoDBReadCapacityUtilization}


## Combined DAX + DynamoDB Sizing Strategy

### 1. Start Small
DynamoDB: On-Demand mode
DAX: 3 × dax.t3.small nodes


### 2. Monitor for 1-2 Weeks

Key metrics:
- DynamoDB consumed capacity
- DAX cache hit rate
- DAX memory utilization
- Request latency

### 3. Optimize Based on Patterns

High read traffic + predictable:
DynamoDB: Switch to Provisioned with auto-scaling
DAX: Upgrade to dax.r5.large


Unpredictable spikes:
DynamoDB: Keep On-Demand
DAX: Add more nodes (scale to 5-6)


Large working set:
DAX: Upgrade node type (dax.r5.xlarge)


## Cost Optimization Tips

1. Right-size DAX working set:
python
# Monitor what's actually cached
# If cache hit rate < 80%, DAX might not be worth it


2. Use DynamoDB On-Demand initially:
- No capacity planning needed
- Switch to Provisioned after understanding patterns

3. Set appropriate TTL:
bash
# Reduce cache TTL if data changes frequently
aws dax update-cluster \
  --cluster-name my-dax-cluster \
  --parameter-group-name custom-params


4. Monitor and adjust:
bash
# Check actual usage monthly
aws dynamodb describe-table --table-name products
aws dax describe-clusters --cluster-name my-dax-cluster


## Quick Decision Matrix

| Scenario | DynamoDB Mode | DAX Setup |
|----------|---------------|-----------|
| New app, unknown traffic | On-Demand | 3 × dax.t3.small |
| Steady 1000 req/s | Provisioned + Auto-scaling | 3 × dax.r5.large |
| Read-heavy, 10GB working set | On-Demand or Provisioned | 3 × dax.r5.large |
| Spiky traffic | On-Demand | 5 × dax.r5.large |
| Cost-sensitive | Provisioned | Skip DAX if hit rate < 80% |

Start conservative, monitor, then scale based on actual usage patterns.


## Key Metrics to Check DAX Right-Sizing

### 1. Cache Hit Rate (Most Important)

bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/DAX \
  --metric-name ItemCacheHits \
  --dimensions Name=ClusterName,Value=my-dax-cluster \
  --start-time 2026-02-06T00:00:00Z \
  --end-time 2026-02-07T16:00:00Z \
  --period 3600 \
  --statistics Sum


Target: >80% hit rate
- <80% → DAX may not be worth it or undersized
- >90% → Well-sized
- >95% → Excellent

### 2. CPU Utilization

bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/DAX \
  --metric-name CPUUtilization \
  --dimensions Name=ClusterName,Value=my-dax-cluster \
  --start-time 2026-02-06T00:00:00Z \
  --end-time 2026-02-07T16:00:00Z \
  --period 3600 \
  --statistics Average


Target: 40-70%
- <40% → Over-provisioned (can downsize)
- 40-70% → Right-sized
- >70% → Under-provisioned (need more nodes or larger type)

### 3. Memory Utilization

bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/DAX \
  --metric-name MemoryUtilization \
  --dimensions Name=ClusterName,Value=my-dax-cluster \
  --start-time 2026-02-06T00:00:00Z \
  --end-time 2026-02-07T16:00:00Z \
  --period 3600 \
  --statistics Average


Target: 60-80%
- <60% → Over-provisioned
- 60-80% → Right-sized
- >80% → Under-provisioned (upgrade node type)

### 4. Eviction Rate

bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/DAX \
  --metric-name EvictedItemCount \
  --dimensions Name=ClusterName,Value=my-dax-cluster \
  --start-time 2026-02-06T00:00:00Z \
  --end-time 2026-02-07T16:00:00Z \
  --period 3600 \
  --statistics Sum


Target: Low/minimal
- High evictions → Memory too small (upgrade node type)
- Low evictions → Good

### 5. Request Rate

bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/DAX \
  --metric-name TotalRequestCount \
  --dimensions Name=ClusterName,Value=my-dax-cluster \
  --start-time 2026-02-06T00:00:00Z \
  --end-time 2026-02-07T16:00:00Z \
  --period 3600 \
  --statistics Sum


Compare to node capacity:
- dax.t3.small: ~50K req/s per node
- dax.r5.large: ~100K req/s per node

## Quick Decision Matrix

| Metric | Value | Action |
|--------|-------|--------|
| Cache Hit Rate | <80% | Increase memory or remove DAX |
| Cache Hit Rate | >90% | Well-sized ✓ |
| CPU | <40% | Reduce nodes or downgrade type |
| CPU | >70% | Add nodes or upgrade type |
| Memory | <60% | Downgrade node type |
| Memory | >80% | Upgrade node type |
| Evictions | High | Upgrade node type |
| Evictions | Low | Good ✓ |

## Simple Health Check Script

bash
#!/bin/bash
CLUSTER_NAME="my-dax-cluster"
START_TIME=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S)
END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)

echo "=== DAX Cluster Health Check ==="

# CPU
CPU=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/DAX \
  --metric-name CPUUtilization \
  --dimensions Name=ClusterName,Value=$CLUSTER_NAME \
  --start-time $START_TIME \
  --end-time $END_TIME \
  --period 86400 \
  --statistics Average \
  --query 'Datapoints[0].Average' \
  --output text)
echo "CPU: $CPU%"

# Memory
MEM=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/DAX \
  --metric-name MemoryUtilization \
  --dimensions Name=ClusterName,Value=$CLUSTER_NAME \
  --start-time $START_TIME \
  --end-time $END_TIME \
  --period 86400 \
  --statistics Average \
  --query 'Datapoints[0].Average' \
  --output text)
echo "Memory: $MEM%"

# Recommendations
if (( $(echo "$CPU > 70" | bc -l) )); then
  echo "⚠️  CPU high - Add nodes or upgrade"
fi

if (( $(echo "$MEM > 80" | bc -l) )); then
  echo "⚠️  Memory high - Upgrade node type"
fi


## Right-Sizing Scenarios

Scenario 1: Over-provisioned
CPU: 25%
Memory: 40%
Hit Rate: 92%
→ Action: Reduce from 5 to 3 nodes or downgrade node type


Scenario 2: Under-provisioned (CPU)
CPU: 85%
Memory: 65%
Hit Rate: 88%
→ Action: Add 2 more nodes


Scenario 3: Under-provisioned (Memory)
CPU: 55%
Memory: 90%
Hit Rate: 75%
Evictions: High
→ Action: Upgrade from dax.r5.large to dax.r5.xlarge


Scenario 4: Well-sized
CPU: 60%
Memory: 70%
Hit Rate: 92%
Evictions: Low
→ Action: No changes needed ✓


## Monitor Weekly

Set up CloudWatch alarms:

bash
# CPU alarm
aws cloudwatch put-metric-alarm \
  --alarm-name dax-high-cpu \
  --metric-name CPUUtilization \
  --namespace AWS/DAX \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 70 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ClusterName,Value=my-dax-cluster

# Memory alarm
aws cloudwatch put-metric-alarm \
  --alarm-name dax-high-memory \
  --metric-name MemoryUtilization \
  --namespace AWS/DAX \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ClusterName,Value=my-dax-cluster


Check these metrics weekly and adjust sizing based on trends, not single data points.


### Caching Best Practices Summary

1. Use DAX for all operations - Reads and writes
2. Let DAX handle cache invalidation - Automatic on writes
3. Implement fallback - To DynamoDB if DAX fails
4. Batch operations - For multiple items
5. Warm cache - Preload frequently accessed items
6. Monitor cache hit rate - Ensure >80% effectiveness
7. Use conditional writes - Prevent stale data issues
8. Set appropriate TTL - Balance freshness vs performance
## Lambda in VPC Connecting to DynamoDB

### Short Answer

YES, Lambda in VPC can connect to DynamoDB in 3 ways:

1. VPC Endpoint (Gateway) - Recommended, free
2. NAT Gateway - Works but costs money
3. Public Internet - Not possible from private subnet without NAT

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Option 1: VPC Endpoint (Gateway) - RECOMMENDED

### What It Is

VPC Gateway Endpoint for DynamoDB - Direct private connection from VPC to DynamoDB without internet

Lambda (VPC) → VPC Endpoint → DynamoDB
              (Private AWS network)


### Benefits

✅ Free (no data transfer charges)
✅ Fast (stays on AWS network)
✅ Secure (no internet exposure)
✅ No NAT Gateway needed

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Implementation

#### Step 1: Create VPC Endpoint

bash
# Get route table IDs for your private subnets
RT_ID=$(aws ec2 describe-route-tables \
  --filters Name=association.subnet-id,Values=subnet-xxxxx \
  --query 'RouteTables[0].RouteTableId' \
  --output text)

# Create DynamoDB VPC endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxxxx \
  --service-name com.amazonaws.us-east-1.dynamodb \
  --route-table-ids $RT_ID \
  --vpc-endpoint-type Gateway

# Output: VPC Endpoint ID (vpce-xxxxx)


#### Step 2: Lambda Function Code

javascript
// index.js - Lambda in VPC accessing DynamoDB
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand, GetCommand } = require('@aws-sdk/lib-dynamodb');

// Create DynamoDB client (automatically uses VPC endpoint)
const client = new DynamoDBClient({ region: 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(client);

exports.handler = async (event) => {
  try {
    // Put item
    await docClient.send(new PutCommand({
      TableName: 'products',
      Item: {
        id: '123',
        name: 'Product Name',
        price: 99.99
      }
    }));
    
    // Get item
    const result = await docClient.send(new GetCommand({
      TableName: 'products',
      Key: { id: '123' }
    }));
    
    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'Success',
        item: result.Item
      })
    };
    
  } catch (error) {
    console.error('Error:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: error.message })
    };
  }
};


#### Step 3: Deploy Lambda

bash
# Package
npm install @aws-sdk/client-dynamodb @aws-sdk/lib-dynamodb
zip -r function.zip index.js node_modules/

# Deploy Lambda in VPC
aws lambda create-function \
  --function-name dynamodb-vpc-function \
  --runtime nodejs18.x \
  --role arn:aws:iam::ACCOUNT:role/lambda-vpc-role \
  --handler index.handler \
  --zip-file fileb://function.zip \
  --vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-lambda \
  --timeout 30


#### Step 4: Test

bash
# Invoke Lambda
aws lambda invoke \
  --function-name dynamodb-vpc-function \
  --payload '{}' \
  response.json

# View response
cat response.json


Output:
json
{
  "statusCode": 200,
  "body": "{\"message\":\"Success\",\"item\":{\"id\":\"123\",\"name\":\"Product Name\",\"price\":99.99}}"
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### How It Works

1. Lambda in private subnet invokes DynamoDB API
   ↓
2. Request routed to VPC endpoint (via route table)
   ↓
3. VPC endpoint forwards to DynamoDB service
   ↓
4. DynamoDB processes request
   ↓
5. Response returns via VPC endpoint
   ↓
6. Lambda receives response

All traffic stays on AWS private network
No internet required


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Option 2: NAT Gateway

### What It Is

NAT Gateway - Allows Lambda in private subnet to access internet (including DynamoDB public endpoint)

Lambda (VPC) → NAT Gateway → Internet Gateway → DynamoDB


### Benefits

✅ Works for DynamoDB and other AWS services
✅ Also allows access to external APIs

### Drawbacks

❌ Costs money ($0.045/hour + $0.045/GB = ~$33/month + data transfer)
❌ Slower than VPC endpoint
❌ More complex setup

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Implementation

bash
# Create NAT Gateway in public subnet
aws ec2 create-nat-gateway \
  --subnet-id subnet-public \
  --allocation-id eipalloc-xxxxx

# Update private subnet route table
aws ec2 create-route \
  --route-table-id rtb-private \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id nat-xxxxx


Lambda code: Same as Option 1 (no changes needed)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Option 3: Public Subnet (NOT RECOMMENDED)

### What It Is

Lambda in public subnet - Lambda gets public IP and accesses DynamoDB via internet

Lambda (public subnet) → Internet Gateway → DynamoDB


### Why NOT Recommended

❌ Lambda in public subnet is anti-pattern
❌ Security risk
❌ No benefit over VPC endpoint

Don't use this approach.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Example: Lambda + RDS + DynamoDB

### Scenario

Lambda needs to:
- Read from RDS (private)
- Write to DynamoDB (public service)

### Architecture

VPC
├── Private Subnet A
│   ├── Lambda
│   └── RDS
│
├── VPC Endpoint (DynamoDB)
└── Route Table → VPC Endpoint


### Setup

bash
# 1. Create VPC endpoint for DynamoDB
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxxxx \
  --service-name com.amazonaws.us-east-1.dynamodb \
  --route-table-ids rtb-private

# 2. Security groups
# Lambda SG: Allow outbound to RDS (5432)
# RDS SG: Allow inbound from Lambda SG (5432)
# No special SG rules needed for DynamoDB (uses VPC endpoint)


### Lambda Code

javascript
// Lambda accessing both RDS and DynamoDB
const { Client } = require('pg');
const { DynamoDBDocumentClient, PutCommand } = require('@aws-sdk/lib-dynamodb');

const docClient = DynamoDBDocumentClient.from(new DynamoDBClient({ region: 'us-east-1' }));

exports.handler = async (event) => {
  // Connect to RDS (via VPC)
  const pgClient = new Client({
    host: process.env.RDS_HOST,
    port: 5432,
    database: 'mydb',
    user: 'postgres',
    password: process.env.DB_PASSWORD
  });
  
  await pgClient.connect();
  
  try {
    // Read from RDS
    const result = await pgClient.query('SELECT * FROM users WHERE id = $1', [event.userId]);
    const user = result.rows[0];
    
    // Write to DynamoDB (via VPC endpoint)
    await docClient.send(new PutCommand({
      TableName: 'user-activity',
      Item: {
        userId: user.id,
        action: 'login',
        timestamp: new Date().toISOString()
      }
    }));
    
    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'Success', user })
    };
    
  } finally {
    await pgClient.end();
  }
};


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Verify VPC Endpoint is Working

### Check Route Table

bash
# Verify VPC endpoint is in route table
aws ec2 describe-route-tables \
  --route-table-ids rtb-xxxxx \
  --query 'RouteTables[0].Routes'

# Output should include:
# {
#   "DestinationPrefixListId": "pl-xxxxx",  # DynamoDB prefix list
#   "GatewayId": "vpce-xxxxx"               # VPC endpoint
# }


### Check Lambda Logs

bash
# Enable VPC Flow Logs to see traffic
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-xxxxx \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs

# Check Lambda logs
aws logs tail /aws/lambda/dynamodb-vpc-function --follow


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Comparison

### Option 1: VPC Endpoint (Gateway)

VPC Endpoint: $0 (free for DynamoDB)
Data Transfer: $0 (free within region)

Total: $0/month


### Option 2: NAT Gateway

NAT Gateway: $0.045/hour × 730 hours = $32.85/month
Data Transfer: $0.045/GB
Example: 100 GB/month = $4.50

Total: ~$37/month


VPC Endpoint saves $37/month!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Troubleshooting

### Problem 1: Lambda Can't Connect to DynamoDB

Error: "Unable to connect to DynamoDB"

Check:
1. VPC endpoint exists
2. VPC endpoint attached to correct route table
3. Lambda IAM role has DynamoDB permissions


Solution:
bash
# Check VPC endpoint
aws ec2 describe-vpc-endpoints \
  --filters Name=service-name,Values=com.amazonaws.us-east-1.dynamodb

# Check IAM permissions
aws iam get-role-policy \
  --role-name lambda-vpc-role \
  --policy-name dynamodb-policy


### Problem 2: Timeout

Error: "Task timed out after 3.00 seconds"

Cause: No VPC endpoint, Lambda trying to reach internet


Solution: Create VPC endpoint (Option 1)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

### Recommended Approach

| Component | Configuration |
|-----------|---------------|
| Lambda | In private subnet |
| DynamoDB | Public service (managed by AWS) |
| Connection | VPC Gateway Endpoint |
| Cost | Free |
| Security | Private AWS network |

### Setup Steps

1. Create VPC endpoint for DynamoDB
2. Attach endpoint to route table
3. Deploy Lambda in VPC
4. Lambda automatically uses VPC endpoint

### Key Points

✅ VPC endpoint is free and recommended
✅ No code changes needed (AWS SDK automatically uses endpoint)
✅ Works with Lambda in private subnet
✅ No NAT Gateway needed
✅ Traffic stays on AWS network

Bottom line: Lambda in VPC can easily connect to DynamoDB using a free VPC Gateway Endpoint. No internet access or NAT Gateway
required.
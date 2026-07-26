## Lambda in VPC

### What is Lambda in VPC?

Lambda in VPC = Lambda function that can access resources inside your VPC (like RDS, ElastiCache, private APIs)

Without VPC:
Lambda (public) → ❌ Cannot access RDS in private subnet


With VPC:
Lambda (in VPC) → ✅ Can access RDS in private subnet


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## How Lambda in VPC Works

### Architecture

VPC
├── Private Subnet A (us-east-1a)
│   ├── RDS PostgreSQL (primary)
│   └── Lambda ENI (Elastic Network Interface)
│
├── Private Subnet B (us-east-1b)
│   ├── RDS PostgreSQL (standby)
│   └── Lambda ENI
│
└── Security Groups
    ├── Lambda SG (allows outbound to RDS)
    └── RDS SG (allows inbound from Lambda)


### How It Works

1. Lambda creates ENIs in your VPC subnets
2. ENIs get private IPs from your subnet
3. Lambda uses ENIs to communicate with VPC resources
4. Security groups control traffic between Lambda and RDS

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step-by-Step Implementation

### Step 1: Create VPC and Subnets

bash
# Create VPC
aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=lambda-vpc}]'

VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=tag:Name,Values=lambda-vpc \
  --query 'Vpcs[0].VpcId' \
  --output text)

# Create private subnets
aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-subnet-a}]'

aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-subnet-b}]'

SUBNET_A=$(aws ec2 describe-subnets \
  --filters Name=tag:Name,Values=private-subnet-a \
  --query 'Subnets[0].SubnetId' \
  --output text)

SUBNET_B=$(aws ec2 describe-subnets \
  --filters Name=tag:Name,Values=private-subnet-b \
  --query 'Subnets[0].SubnetId' \
  --output text)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 2: Create Security Groups

bash
# Lambda Security Group
aws ec2 create-security-group \
  --group-name lambda-sg \
  --description "Security group for Lambda" \
  --vpc-id $VPC_ID

LAMBDA_SG=$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values=lambda-sg \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

# RDS Security Group
aws ec2 create-security-group \
  --group-name rds-sg \
  --description "Security group for RDS" \
  --vpc-id $VPC_ID

RDS_SG=$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values=rds-sg \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

# Allow Lambda to connect to RDS (port 5432)
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG \
  --protocol tcp \
  --port 5432 \
  --source-group $LAMBDA_SG


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 3: Create RDS PostgreSQL

bash
# Create DB subnet group
aws rds create-db-subnet-group \
  --db-subnet-group-name lambda-db-subnet \
  --db-subnet-group-description "Subnet group for Lambda RDS" \
  --subnet-ids $SUBNET_A $SUBNET_B

# Create RDS PostgreSQL
aws rds create-db-instance \
  --db-instance-identifier lambda-postgres \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username postgres \
  --master-user-password MyPassword123 \
  --allocated-storage 20 \
  --vpc-security-group-ids $RDS_SG \
  --db-subnet-group-name lambda-db-subnet \
  --no-publicly-accessible

# Wait for RDS to be available (5-10 minutes)
aws rds wait db-instance-available \
  --db-instance-identifier lambda-postgres

# Get RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier lambda-postgres \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo "RDS Endpoint: $RDS_ENDPOINT"


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 4: Create IAM Role for Lambda

bash
# Create trust policy
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "lambda.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }]
}
EOF

# Create role
aws iam create-role \
  --role-name lambda-vpc-role \
  --assume-role-policy-document file://trust-policy.json

# Attach policies
aws iam attach-role-policy \
  --role-name lambda-vpc-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole

aws iam attach-role-policy \
  --role-name lambda-vpc-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 5: Create Lambda Function

javascript
// index.js
const { Client } = require('pg');

exports.handler = async (event) => {
  // RDS connection config
  const client = new Client({
    host: process.env.DB_HOST,
    port: 5432,
    database: 'postgres',
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    ssl: false  // Not needed for VPC connection
  });
  
  try {
    // Connect to RDS
    await client.connect();
    console.log('Connected to RDS');
    
    // Query database
    const result = await client.query('SELECT NOW()');
    console.log('Query result:', result.rows[0]);
    
    // Example: Get all users
    const users = await client.query('SELECT * FROM users LIMIT 10');
    
    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'Success',
        timestamp: result.rows[0].now,
        users: users.rows
      })
    };
    
  } catch (error) {
    console.error('Error:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({
        error: error.message
      })
    };
    
  } finally {
    // Close connection
    await client.end();
  }
};


Package Lambda:
bash
# Install dependencies
npm install pg

# Create deployment package
zip -r function.zip index.js node_modules/


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 6: Deploy Lambda in VPC

bash
# Get role ARN
ROLE_ARN=$(aws iam get-role \
  --role-name lambda-vpc-role \
  --query 'Role.Arn' \
  --output text)

# Create Lambda function
aws lambda create-function \
  --function-name rds-connector \
  --runtime nodejs18.x \
  --role $ROLE_ARN \
  --handler index.handler \
  --zip-file fileb://function.zip \
  --timeout 30 \
  --memory-size 512 \
  --vpc-config SubnetIds=$SUBNET_A,$SUBNET_B,SecurityGroupIds=$LAMBDA_SG \
  --environment Variables="{
    DB_HOST=$RDS_ENDPOINT,
    DB_USER=postgres,
    DB_PASSWORD=MyPassword123
  }"


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 7: Test Lambda

bash
# Invoke Lambda
aws lambda invoke \
  --function-name rds-connector \
  --payload '{}' \
  response.json

# View response
cat response.json


Output:
json
{
  "statusCode": 200,
  "body": "{\"message\":\"Success\",\"timestamp\":\"2026-02-09T00:32:00.305Z\",\"users\":[]}"
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Connection Flow

### What Happens When Lambda Runs

1. Lambda invoked
   ↓
2. Lambda uses ENI in VPC
   ↓
3. ENI has private IP (10.0.1.x)
   ↓
4. Lambda connects to RDS endpoint (10.0.1.y:5432)
   ↓
5. Security groups allow traffic
   ↓
6. Connection established
   ↓
7. Query executed
   ↓
8. Connection closed


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Example with Connection Pooling

javascript
// index.js - Better approach with connection reuse
const { Pool } = require('pg');

// Create pool outside handler (reused across invocations)
const pool = new Pool({
  host: process.env.DB_HOST,
  port: 5432,
  database: 'postgres',
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max: 1,  // Lambda: use 1 connection per container
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000
});

exports.handler = async (event) => {
  try {
    // Query using pool (reuses connection)
    const result = await pool.query('SELECT NOW()');
    
    // Example: Insert data
    if (event.action === 'insert') {
      await pool.query(
        'INSERT INTO users (name, email) VALUES ($1, $2)',
        [event.name, event.email]
      );
    }
    
    // Example: Get users
    const users = await pool.query('SELECT * FROM users');
    
    return {
      statusCode: 200,
      body: JSON.stringify({
        timestamp: result.rows[0].now,
        users: users.rows
      })
    };
    
  } catch (error) {
    console.error('Error:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: error.message })
    };
  }
  
  // Don't close pool - it's reused across invocations
};


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Important Considerations

### 1. Cold Start

Problem: Lambda in VPC has slower cold starts (1-3 seconds)

Why: Lambda needs to create ENIs in your VPC

Solution: Use provisioned concurrency
bash
aws lambda put-provisioned-concurrency-config \
  --function-name rds-connector \
  --provisioned-concurrent-executions 2


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 2. Connection Limits

Problem: Each Lambda creates connections to RDS

100 concurrent Lambdas × 1 connection each = 100 RDS connections
RDS db.t3.micro max connections = 87
Result: Connection errors!


Solution: Use RDS Proxy
bash
# Create RDS Proxy
aws rds create-db-proxy \
  --db-proxy-name lambda-proxy \
  --engine-family POSTGRESQL \
  --auth '{
    "AuthScheme": "SECRETS",
    "SecretArn": "arn:aws:secretsmanager:...",
    "IAMAuth": "DISABLED"
  }' \
  --role-arn arn:aws:iam::ACCOUNT:role/rds-proxy-role \
  --vpc-subnet-ids $SUBNET_A $SUBNET_B \
  --require-tls false

# Update Lambda to use proxy endpoint
DB_HOST=lambda-proxy.proxy-xxxxx.us-east-1.rds.amazonaws.com


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 3. Internet Access

Problem: Lambda in VPC cannot access internet by default

Lambda in private subnet → ❌ Cannot call external APIs


Solution: Add NAT Gateway
bash
# Create NAT Gateway in public subnet
aws ec2 create-nat-gateway \
  --subnet-id $PUBLIC_SUBNET \
  --allocation-id $EIP_ALLOCATION

# Update route table for private subnets
aws ec2 create-route \
  --route-table-id $PRIVATE_RT \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id $NAT_GW


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Monitoring

bash
# View Lambda logs
aws logs tail /aws/lambda/rds-connector --follow

# Check ENI creation
aws ec2 describe-network-interfaces \
  --filters Name=description,Values="AWS Lambda VPC ENI*" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,PrivateIpAddress,Status]'

# Monitor RDS connections
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=lambda-postgres \
  --start-time 2026-02-09T00:00:00Z \
  --end-time 2026-02-09T01:00:00Z \
  --period 300 \
  --statistics Average,Maximum


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

### Lambda in VPC Setup

| Component | Configuration |
|-----------|---------------|
| VPC | Private subnets in 2 AZs |
| Lambda SG | Outbound to RDS (5432) |
| RDS SG | Inbound from Lambda SG (5432) |
| Lambda | Attached to private subnets + Lambda SG |
| RDS | In private subnets + RDS SG |
| IAM Role | AWSLambdaVPCAccessExecutionRole |

### Key Points

1. Lambda creates ENIs in your VPC subnets
2. Security groups control Lambda ↔ RDS traffic
3. Use connection pooling to reuse connections
4. Consider RDS Proxy for high concurrency
5. Cold starts are slower (1-3 seconds)
6. No internet access without NAT Gateway

Lambda in VPC allows secure, private access to RDS without exposing database to internet.
## Lambda in VPC + API Gateway Integration

### Short Answer

YES, API Gateway can invoke Lambda in VPC.

API Gateway is PUBLIC by default (but can be made private).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## How It Works

### Architecture

Internet
  ↓
API Gateway (Public)
  ↓
AWS Internal Network (Managed by AWS)
  ↓
Lambda in VPC
  ↓
RDS/Resources in VPC


Key Point: API Gateway to Lambda connection is managed by AWS, NOT through your VPC.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## API Gateway Types

### 1. Edge-Optimized API (Default)

Public, globally distributed

User (anywhere) → CloudFront Edge → API Gateway → Lambda in VPC


- Accessible from internet
- Uses CloudFront for global distribution
- Best for public APIs

### 2. Regional API

Public, single region

User → API Gateway (us-east-1) → Lambda in VPC


- Accessible from internet
- Single region deployment
- Lower latency for regional users

### 3. Private API

Private, VPC only

User in VPC → VPC Endpoint → API Gateway (Private) → Lambda in VPC


- NOT accessible from internet
- Requires VPC endpoint
- For internal APIs only

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Implementation: Public API Gateway + Lambda in VPC

### Step 1: Create Lambda in VPC

bash
# Lambda function code
cat > index.js <<EOF
const { Client } = require('pg');

exports.handler = async (event) => {
  const client = new Client({
    host: process.env.RDS_HOST,
    port: 5432,
    database: 'mydb',
    user: 'postgres',
    password: process.env.DB_PASSWORD
  });
  
  await client.connect();
  
  try {
    const result = await client.query('SELECT * FROM products LIMIT 10');
    
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify(result.rows)
    };
  } finally {
    await client.end();
  }
};
EOF

# Package and deploy
npm install pg
zip -r function.zip index.js node_modules/

aws lambda create-function \
  --function-name api-backend \
  --runtime nodejs18.x \
  --role arn:aws:iam::ACCOUNT:role/lambda-vpc-role \
  --handler index.handler \
  --zip-file fileb://function.zip \
  --vpc-config SubnetIds=subnet-a,subnet-b,SecurityGroupIds=sg-lambda \
  --environment Variables="{RDS_HOST=rds-endpoint.amazonaws.com,DB_PASSWORD=password}" \
  --timeout 30


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 2: Create API Gateway

bash
# Create REST API
aws apigateway create-rest-api \
  --name products-api \
  --endpoint-configuration types=REGIONAL

API_ID=$(aws apigateway get-rest-apis \
  --query 'items[?name==`products-api`].id' \
  --output text)

# Get root resource
ROOT_ID=$(aws apigateway get-resources \
  --rest-api-id $API_ID \
  --query 'items[?path==`/`].id' \
  --output text)

# Create /products resource
aws apigateway create-resource \
  --rest-api-id $API_ID \
  --parent-id $ROOT_ID \
  --path-part products

RESOURCE_ID=$(aws apigateway get-resources \
  --rest-api-id $API_ID \
  --query 'items[?path==`/products`].id' \
  --output text)

# Create GET method
aws apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method GET \
  --authorization-type NONE

# Integrate with Lambda
aws apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:ACCOUNT:function:api-backend/invocations

# Grant API Gateway permission to invoke Lambda
aws lambda add-permission \
  --function-name api-backend \
  --statement-id apigateway-invoke \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:us-east-1:ACCOUNT:$API_ID/*/*"

# Deploy API
aws apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name prod


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 3: Test

bash
# Get API endpoint
API_ENDPOINT="https://$API_ID.execute-api.us-east-1.amazonaws.com/prod"

# Test API
curl $API_ENDPOINT/products

# Output: JSON array of products from RDS


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Connection Flow

### Public API Gateway → Lambda in VPC

1. User makes HTTP request
   ↓
2. API Gateway receives request (public endpoint)
   ↓
3. API Gateway invokes Lambda (AWS internal network)
   ↓
4. Lambda execution environment created in VPC
   ↓
5. Lambda uses ENI to access RDS in VPC
   ↓
6. Lambda returns response to API Gateway
   ↓
7. API Gateway returns response to user


Important: API Gateway to Lambda connection does NOT go through your VPC.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Network Diagram

┌─────────────────────────────────────────────────────────┐
│ Internet (Public)                                        │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ API Gateway (Public)                                     │
│ https://abc123.execute-api.us-east-1.amazonaws.com      │
└─────────────────────────────────────────────────────────┘
                          ↓
              AWS Internal Network
              (Managed by AWS)
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Your VPC                                                 │
│                                                          │
│  ┌────────────────────────────────────────────┐        │
│  │ Private Subnet A                            │        │
│  │  ├── Lambda (ENI: 10.0.1.45)               │        │
│  │  └── RDS (10.0.1.100:5432)                 │        │
│  └────────────────────────────────────────────┘        │
│                                                          │
│  ┌────────────────────────────────────────────┐        │
│  │ Private Subnet B                            │        │
│  │  ├── Lambda (ENI: 10.0.2.67)               │        │
│  │  └── RDS Standby (10.0.2.100:5432)         │        │
│  └────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────┘


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Private API Gateway (VPC Only)

### When to Use

- Internal APIs only
- No internet access needed
- Extra security

### Implementation

bash
# Create VPC endpoint for API Gateway
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxxxx \
  --service-name com.amazonaws.us-east-1.execute-api \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-a subnet-b \
  --security-group-ids sg-api-endpoint

# Create private API
aws apigateway create-rest-api \
  --name private-api \
  --endpoint-configuration types=PRIVATE \
  --policy '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": "*",
      "Action": "execute-api:Invoke",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:SourceVpce": "vpce-xxxxx"
        }
      }
    }]
  }'


Access:
bash
# Only accessible from within VPC
curl https://abc123-vpce-xxxxx.execute-api.us-east-1.amazonaws.com/prod/products

# NOT accessible from internet
curl https://abc123.execute-api.us-east-1.amazonaws.com/prod/products
# Error: Forbidden


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Security Considerations

### 1. API Gateway is Public (Default)

Anyone on internet can call your API
└── Use authentication/authorization


Solutions:
- API Keys
- IAM authorization
- Cognito authorizer
- Lambda authorizer
- WAF

### 2. Lambda in VPC is Private

Lambda cannot be accessed directly from internet
└── Only through API Gateway


### 3. RDS is Private

RDS only accessible from within VPC
└── Lambda can access, API Gateway cannot


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Example with Authentication

javascript
// Lambda with Cognito authentication
exports.handler = async (event) => {
  // Get user info from Cognito authorizer
  const userId = event.requestContext.authorizer.claims.sub;
  
  console.log('User:', userId);
  
  // Connect to RDS in VPC
  const client = new Client({
    host: process.env.RDS_HOST,
    port: 5432,
    database: 'mydb',
    user: 'postgres',
    password: process.env.DB_PASSWORD
  });
  
  await client.connect();
  
  try {
    // Get user-specific data
    const result = await client.query(
      'SELECT * FROM orders WHERE user_id = $1',
      [userId]
    );
    
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify(result.rows)
    };
    
  } finally {
    await client.end();
  }
};


API Gateway with Cognito:
bash
aws apigateway create-authorizer \
  --rest-api-id $API_ID \
  --name cognito-authorizer \
  --type COGNITO_USER_POOLS \
  --provider-arns arn:aws:cognito-idp:us-east-1:ACCOUNT:userpool/us-east-1_XXXXX \
  --identity-source method.request.header.Authorization


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

### API Gateway Types

| Type | Public? | Use Case |
|------|---------|----------|
| Edge-Optimized | ✅ Yes | Global public APIs |
| Regional | ✅ Yes | Regional public APIs |
| Private | ❌ No | Internal VPC-only APIs |

### Integration Flow

Public API Gateway:
Internet → API Gateway (public) → Lambda in VPC → RDS (private)

Private API Gateway:
VPC → VPC Endpoint → API Gateway (private) → Lambda in VPC → RDS (private)


### Key Points

1. API Gateway is public by default - Accessible from internet
2. Lambda in VPC is private - Not directly accessible
3. API Gateway → Lambda connection is managed by AWS - Not through your VPC
4. Lambda → RDS connection is through VPC - Uses ENIs
5. No special VPC configuration needed for API Gateway integration
6. Use authentication to secure public API Gateway

Bottom line: API Gateway (public) can easily invoke Lambda in VPC. The connection between them is managed by AWS and doesn't 
require any VPC configuration. Your Lambda can then access private resources (like RDS) within the VPC.
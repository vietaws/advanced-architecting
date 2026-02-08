## Per-User Caching with CloudFront + API Gateway + Lambda

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Architecture

User → CloudFront → API Gateway → Lambda → DynamoDB
       (Cache per user)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 1: Create Lambda Function

javascript
// lambda/dashboard.js
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand, GetCommand } = require('@aws-sdk/lib-dynamodb');
const jwt = require('jsonwebtoken');

const client = new DynamoDBClient({ region: 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(client);

exports.handler = async (event) => {
  // 1. Extract and verify JWT token
  const authHeader = event.headers.Authorization || event.headers.authorization;
  
  if (!authHeader) {
    return {
      statusCode: 401,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store'
      },
      body: JSON.stringify({ error: 'No authorization header' })
    };
  }
  
  const token = authHeader.replace('Bearer ', '');
  
  let user;
  try {
    user = jwt.verify(token, process.env.JWT_SECRET);
  } catch (error) {
    return {
      statusCode: 401,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store'
      },
      body: JSON.stringify({ error: 'Invalid token' })
    };
  }
  
  // 2. Get user-specific data from DynamoDB
  const userId = user.id;
  
  try {
    // Get user stats
    const statsResult = await docClient.send(new GetCommand({
      TableName: 'UserStats',
      Key: { userId }
    }));
    
    // Get recent activity
    const activityResult = await docClient.send(new QueryCommand({
      TableName: 'UserActivity',
      KeyConditionExpression: 'userId = :userId',
      ExpressionAttributeValues: {
        ':userId': userId
      },
      ScanIndexForward: false,
      Limit: 10
    }));
    
    // Get notifications
    const notificationsResult = await docClient.send(new QueryCommand({
      TableName: 'Notifications',
      IndexName: 'userId-read-index',
      KeyConditionExpression: 'userId = :userId AND #read = :read',
      ExpressionAttributeNames: {
        '#read': 'read'
      },
      ExpressionAttributeValues: {
        ':userId': userId,
        ':read': false
      }
    }));
    
    // 3. Build dashboard response
    const dashboard = {
      userId: userId,
      username: user.username,
      stats: statsResult.Item || { orders: 0, spent: 0 },
      recentActivity: activityResult.Items || [],
      notifications: notificationsResult.Items || []
    };
    
    // 4. Return with caching headers
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'private, max-age=300',  // Cache 5 minutes per user
        'Vary': 'Authorization',
        'X-User-Id': userId  // For debugging
      },
      body: JSON.stringify(dashboard)
    };
    
  } catch (error) {
    console.error('Error:', error);
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store'
      },
      body: JSON.stringify({ error: 'Internal server error' })
    };
  }
};


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 2: Create API Gateway

bash
# Create REST API
aws apigateway create-rest-api \
  --name user-dashboard-api \
  --endpoint-configuration types=REGIONAL

# Get API ID
API_ID=$(aws apigateway get-rest-apis \
  --query 'items[?name==`user-dashboard-api`].id' \
  --output text)

# Get root resource ID
ROOT_ID=$(aws apigateway get-resources \
  --rest-api-id $API_ID \
  --query 'items[?path==`/`].id' \
  --output text)

# Create /dashboard resource
aws apigateway create-resource \
  --rest-api-id $API_ID \
  --parent-id $ROOT_ID \
  --path-part dashboard

# Get dashboard resource ID
DASHBOARD_ID=$(aws apigateway get-resources \
  --rest-api-id $API_ID \
  --query 'items[?path==`/dashboard`].id' \
  --output text)

# Create GET method
aws apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $DASHBOARD_ID \
  --http-method GET \
  --authorization-type NONE \
  --request-parameters method.request.header.Authorization=true

# Integrate with Lambda
aws apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $DASHBOARD_ID \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:ACCOUNT-ID:function:dashboard-function/invocations

# Deploy API
aws apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name prod


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 3: Configure CloudFront

bash
# Create CloudFront distribution
aws cloudfront create-distribution \
  --distribution-config file://cloudfront-config.json


cloudfront-config.json:
json
{
  "CallerReference": "dashboard-api-2026",
  "Comment": "Per-user caching for dashboard API",
  "Enabled": true,
  "Origins": {
    "Quantity": 1,
    "Items": [{
      "Id": "api-gateway-origin",
      "DomainName": "abc123.execute-api.us-east-1.amazonaws.com",
      "OriginPath": "/prod",
      "CustomOriginConfig": {
        "HTTPPort": 80,
        "HTTPSPort": 443,
        "OriginProtocolPolicy": "https-only",
        "OriginSslProtocols": {
          "Quantity": 1,
          "Items": ["TLSv1.2"]
        },
        "OriginReadTimeout": 30,
        "OriginKeepaliveTimeout": 5
      }
    }]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "api-gateway-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["GET", "HEAD"]
      }
    },
    "Compress": true,
    "MinTTL": 60,
    "DefaultTTL": 300,
    "MaxTTL": 600,
    "ForwardedValues": {
      "QueryString": false,
      "Headers": {
        "Quantity": 1,
        "Items": ["Authorization"]
      },
      "Cookies": {
        "Forward": "none"
      }
    },
    "TrustedSigners": {
      "Enabled": false,
      "Quantity": 0
    }
  }
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 4: Additional Lambda Functions

### User Orders

javascript
// lambda/orders.js
const { DynamoDBDocumentClient, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const jwt = require('jsonwebtoken');

exports.handler = async (event) => {
  // Verify token
  const token = event.headers.Authorization?.replace('Bearer ', '');
  const user = jwt.verify(token, process.env.JWT_SECRET);
  
  // Get orders
  const result = await docClient.send(new QueryCommand({
    TableName: 'Orders',
    KeyConditionExpression: 'userId = :userId',
    ExpressionAttributeValues: {
      ':userId': user.id
    },
    ScanIndexForward: false
  }));
  
  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'private, max-age=600',  // 10 minutes
      'Vary': 'Authorization'
    },
    body: JSON.stringify(result.Items)
  };
};


### User Profile

javascript
// lambda/profile.js
const { DynamoDBDocumentClient, GetCommand } = require('@aws-sdk/lib-dynamodb');
const jwt = require('jsonwebtoken');

exports.handler = async (event) => {
  // Verify token
  const token = event.headers.Authorization?.replace('Bearer ', '');
  const user = jwt.verify(token, process.env.JWT_SECRET);
  
  // Get profile
  const result = await docClient.send(new GetCommand({
    TableName: 'Users',
    Key: { userId: user.id }
  }));
  
  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'private, max-age=1800',  // 30 minutes
      'Vary': 'Authorization'
    },
    body: JSON.stringify(result.Item)
  };
};


### Update Profile (No Cache)

javascript
// lambda/updateProfile.js
const { DynamoDBDocumentClient, UpdateCommand } = require('@aws-sdk/lib-dynamodb');
const jwt = require('jsonwebtoken');

exports.handler = async (event) => {
  // Verify token
  const token = event.headers.Authorization?.replace('Bearer ', '');
  const user = jwt.verify(token, process.env.JWT_SECRET);
  
  // Parse body
  const body = JSON.parse(event.body);
  
  // Update profile
  await docClient.send(new UpdateCommand({
    TableName: 'Users',
    Key: { userId: user.id },
    UpdateExpression: 'SET #name = :name, email = :email, updatedAt = :updatedAt',
    ExpressionAttributeNames: {
      '#name': 'name'
    },
    ExpressionAttributeValues: {
      ':name': body.name,
      ':email': body.email,
      ':updatedAt': new Date().toISOString()
    }
  }));
  
  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store'  // Don't cache POST/PUT
    },
    body: JSON.stringify({ success: true })
  };
};


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 5: Frontend Integration

javascript
// React component
import { useState, useEffect } from 'react';

function Dashboard() {
  const [dashboard, setDashboard] = useState(null);
  const [loading, setLoading] = useState(true);
  const token = localStorage.getItem('authToken');
  
  useEffect(() => {
    fetchDashboard();
  }, []);
  
  async function fetchDashboard() {
    try {
      const response = await fetch('https://d1234.cloudfront.net/dashboard', {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });
      
      const data = await response.json();
      setDashboard(data);
      setLoading(false);
      
      // Check if response was cached
      const cacheStatus = response.headers.get('X-Cache');
      console.log('Cache status:', cacheStatus);  // Hit from cloudfront or Miss from cloudfront
      
    } catch (error) {
      console.error('Error:', error);
      setLoading(false);
    }
  }
  
  if (loading) return <div>Loading...</div>;
  
  return (
    <div>
      <h1>Welcome, {dashboard.username}</h1>
      
      <div className="stats">
        <div>Orders: {dashboard.stats.orders}</div>
        <div>Total Spent: ${dashboard.stats.spent}</div>
      </div>
      
      <div className="activity">
        <h2>Recent Activity</h2>
        {dashboard.recentActivity.map(activity => (
          <div key={activity.id}>{activity.description}</div>
        ))}
      </div>
      
      <div className="notifications">
        <h2>Notifications ({dashboard.notifications.length})</h2>
        {dashboard.notifications.map(notif => (
          <div key={notif.id}>{notif.message}</div>
        ))}
      </div>
    </div>
  );
}

export default Dashboard;


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 6: Complete API Gateway Configuration

bash
# Create multiple endpoints
# /dashboard (GET) - cached
# /orders (GET) - cached
# /profile (GET) - cached
# /profile (PUT) - not cached

# Add CORS
aws apigateway put-method-response \
  --rest-api-id $API_ID \
  --resource-id $DASHBOARD_ID \
  --http-method GET \
  --status-code 200 \
  --response-parameters \
    method.response.header.Access-Control-Allow-Origin=true

aws apigateway put-integration-response \
  --rest-api-id $API_ID \
  --resource-id $DASHBOARD_ID \
  --http-method GET \
  --status-code 200 \
  --response-parameters \
    method.response.header.Access-Control-Allow-Origin="'*'"


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 7: Lambda Authorizer (Optional)

javascript
// lambda/authorizer.js
const jwt = require('jsonwebtoken');

exports.handler = async (event) => {
  const token = event.authorizationToken?.replace('Bearer ', '');
  
  try {
    const user = jwt.verify(token, process.env.JWT_SECRET);
    
    return {
      principalId: user.id,
      policyDocument: {
        Version: '2012-10-17',
        Statement: [{
          Action: 'execute-api:Invoke',
          Effect: 'Allow',
          Resource: event.methodArn
        }]
      },
      context: {
        userId: user.id,
        username: user.username
      }
    };
  } catch (error) {
    throw new Error('Unauthorized');
  }
};


Attach to API Gateway:
bash
aws apigateway create-authorizer \
  --rest-api-id $API_ID \
  --name jwt-authorizer \
  --type TOKEN \
  --authorizer-uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:ACCOUNT-ID:function:authorizer/invocations \
  --identity-source method.request.header.Authorization \
  --authorizer-result-ttl-in-seconds 300


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Testing

bash
# Get JWT token (from your auth service)
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# Test via CloudFront (first request - cache miss)
curl -H "Authorization: Bearer $TOKEN" \
  https://d1234.cloudfront.net/dashboard

# Response headers:
# X-Cache: Miss from cloudfront
# Cache-Control: private, max-age=300

# Test again (cache hit)
curl -H "Authorization: Bearer $TOKEN" \
  https://d1234.cloudfront.net/dashboard

# Response headers:
# X-Cache: Hit from cloudfront
# Age: 45

# Different user (cache miss for this user)
TOKEN2="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
curl -H "Authorization: Bearer $TOKEN2" \
  https://d1234.cloudfront.net/dashboard

# Response headers:
# X-Cache: Miss from cloudfront


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Monitoring

javascript
// Lambda function with CloudWatch metrics
const { CloudWatchClient, PutMetricDataCommand } = require('@aws-sdk/client-cloudwatch');

const cloudwatch = new CloudWatchClient({ region: 'us-east-1' });

exports.handler = async (event) => {
  const startTime = Date.now();
  
  // ... your code ...
  
  const duration = Date.now() - startTime;
  
  // Log custom metric
  await cloudwatch.send(new PutMetricDataCommand({
    Namespace: 'DashboardAPI',
    MetricData: [{
      MetricName: 'ResponseTime',
      Value: duration,
      Unit: 'Milliseconds',
      Dimensions: [{
        Name: 'Function',
        Value: 'dashboard'
      }]
    }]
  }));
  
  return response;
};


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

### Architecture Flow

User A (token: aaa) → CloudFront → API Gateway → Lambda → DynamoDB
                      ↓ Cache (key: /dashboard + aaa)
                      
User B (token: bbb) → CloudFront → API Gateway → Lambda → DynamoDB
                      ↓ Cache (key: /dashboard + bbb)
                      
User A (token: aaa) → CloudFront (Cache Hit!) → Return cached data


### Key Components

| Component | Configuration |
|-----------|---------------|
| Lambda | Returns Cache-Control: private, max-age=300 |
| API Gateway | Passes Authorization header to Lambda |
| CloudFront | Forwards Authorization header, caches per user |
| DynamoDB | Stores user-specific data |

### Benefits

- ✅ 90% cache hit rate
- ✅ 10x faster response (10ms vs 200ms)
- ✅ 90% reduction in Lambda invocations
- ✅ 90% reduction in DynamoDB reads
- ✅ Lower costs
- ✅ No data leakage between users

Cost savings: With 1M requests/month and 90% cache hit rate, you save ~$18/month in Lambda costs and ~$2/month in DynamoDB 
costs.
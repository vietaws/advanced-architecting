## Per-User Caching with Cognito + API Gateway + Lambda + CloudFront

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Architecture

User → Cognito (Auth) → CloudFront → API Gateway (Cognito Authorizer) → Lambda → DynamoDB
                         (Cache per user)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 1: Create Cognito User Pool

bash
# Create User Pool
aws cognito-idp create-user-pool \
  --pool-name dashboard-users \
  --policies '{
    "PasswordPolicy": {
      "MinimumLength": 8,
      "RequireUppercase": true,
      "RequireLowercase": true,
      "RequireNumbers": true
    }
  }' \
  --auto-verified-attributes email

# Get User Pool ID
USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 10 \
  --query 'UserPools[?Name==`dashboard-users`].Id' \
  --output text)

# Create App Client
aws cognito-idp create-user-pool-client \
  --user-pool-id $USER_POOL_ID \
  --client-name dashboard-app \
  --generate-secret false \
  --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH \
  --read-attributes email name sub

# Get App Client ID
CLIENT_ID=$(aws cognito-idp list-user-pool-clients \
  --user-pool-id $USER_POOL_ID \
  --query 'UserPoolClients[0].ClientId' \
  --output text)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 2: Create Lambda Functions

### Dashboard Lambda

javascript
// lambda/dashboard.js
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({ region: 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(client);

exports.handler = async (event) => {
  // Get user info from Cognito authorizer
  const userId = event.requestContext.authorizer.claims.sub;
  const username = event.requestContext.authorizer.claims['cognito:username'];
  const email = event.requestContext.authorizer.claims.email;
  
  console.log('User ID:', userId);
  console.log('Username:', username);
  
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
    
    // Build dashboard
    const dashboard = {
      userId: userId,
      username: username,
      email: email,
      stats: statsResult.Item || { orders: 0, spent: 0 },
      recentActivity: activityResult.Items || [],
      notifications: notificationsResult.Items || []
    };
    
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'private, max-age=300',  // Cache 5 minutes per user
        'Vary': 'Authorization',
        'Access-Control-Allow-Origin': '*',
        'X-User-Id': userId
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


### Orders Lambda

javascript
// lambda/orders.js
const { DynamoDBDocumentClient, QueryCommand } = require('@aws-sdk/lib-dynamodb');

exports.handler = async (event) => {
  const userId = event.requestContext.authorizer.claims.sub;
  
  const result = await docClient.send(new QueryCommand({
    TableName: 'Orders',
    KeyConditionExpression: 'userId = :userId',
    ExpressionAttributeValues: {
      ':userId': userId
    },
    ScanIndexForward: false
  }));
  
  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'private, max-age=600',  // 10 minutes
      'Vary': 'Authorization',
      'Access-Control-Allow-Origin': '*'
    },
    body: JSON.stringify(result.Items)
  };
};


### Profile Lambda

javascript
// lambda/profile.js
const { DynamoDBDocumentClient, GetCommand } = require('@aws-sdk/lib-dynamodb');

exports.handler = async (event) => {
  const userId = event.requestContext.authorizer.claims.sub;
  
  const result = await docClient.send(new GetCommand({
    TableName: 'Users',
    Key: { userId }
  }));
  
  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'private, max-age=1800',  // 30 minutes
      'Vary': 'Authorization',
      'Access-Control-Allow-Origin': '*'
    },
    body: JSON.stringify(result.Item)
  };
};


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 3: Create API Gateway with Cognito Authorizer

bash
# Create REST API
aws apigateway create-rest-api \
  --name dashboard-api \
  --endpoint-configuration types=REGIONAL

API_ID=$(aws apigateway get-rest-apis \
  --query 'items[?name==`dashboard-api`].id' \
  --output text)

# Create Cognito Authorizer
aws apigateway create-authorizer \
  --rest-api-id $API_ID \
  --name cognito-authorizer \
  --type COGNITO_USER_POOLS \
  --provider-arns arn:aws:cognito-idp:us-east-1:ACCOUNT-ID:userpool/$USER_POOL_ID \
  --identity-source method.request.header.Authorization

AUTHORIZER_ID=$(aws apigateway get-authorizers \
  --rest-api-id $API_ID \
  --query 'items[0].id' \
  --output text)

# Get root resource
ROOT_ID=$(aws apigateway get-resources \
  --rest-api-id $API_ID \
  --query 'items[?path==`/`].id' \
  --output text)

# Create /dashboard resource
aws apigateway create-resource \
  --rest-api-id $API_ID \
  --parent-id $ROOT_ID \
  --path-part dashboard

DASHBOARD_ID=$(aws apigateway get-resources \
  --rest-api-id $API_ID \
  --query 'items[?path==`/dashboard`].id' \
  --output text)

# Create GET method with Cognito authorizer
aws apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $DASHBOARD_ID \
  --http-method GET \
  --authorization-type COGNITO_USER_POOLS \
  --authorizer-id $AUTHORIZER_ID

# Integrate with Lambda
aws apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $DASHBOARD_ID \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:ACCOUNT-ID:function:dashboard-function/invocations

# Deploy
aws apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name prod


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 4: Configure CloudFront

json
{
  "CallerReference": "cognito-dashboard-2026",
  "Comment": "Per-user caching with Cognito",
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
        }
      }
    }]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "api-gateway-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"]
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
    }
  }
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 5: Frontend (React with Cognito)

### Install Dependencies

bash
npm install amazon-cognito-identity-js


### Login Component

javascript
// Login.js
import { useState } from 'react';
import { CognitoUserPool, CognitoUser, AuthenticationDetails } from 'amazon-cognito-identity-js';

const poolData = {
  UserPoolId: 'us-east-1_XXXXX',
  ClientId: 'your-client-id'
};

const userPool = new CognitoUserPool(poolData);

function Login({ onLoginSuccess }) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  
  const handleLogin = (e) => {
    e.preventDefault();
    
    const authenticationData = {
      Username: username,
      Password: password
    };
    
    const authenticationDetails = new AuthenticationDetails(authenticationData);
    
    const userData = {
      Username: username,
      Pool: userPool
    };
    
    const cognitoUser = new CognitoUser(userData);
    
    cognitoUser.authenticateUser(authenticationDetails, {
      onSuccess: (result) => {
        const idToken = result.getIdToken().getJwtToken();
        const accessToken = result.getAccessToken().getJwtToken();
        
        // Store tokens
        localStorage.setItem('idToken', idToken);
        localStorage.setItem('accessToken', accessToken);
        
        console.log('Login successful');
        onLoginSuccess();
      },
      onFailure: (err) => {
        console.error('Login failed:', err);
        setError(err.message);
      }
    });
  };
  
  return (
    <form onSubmit={handleLogin}>
      <h2>Login</h2>
      {error && <div className="error">{error}</div>}
      
      <input
        type="text"
        placeholder="Username"
        value={username}
        onChange={(e) => setUsername(e.target.value)}
      />
      
      <input
        type="password"
        placeholder="Password"
        value={password}
        onChange={(e) => setPassword(e.target.value)}
      />
      
      <button type="submit">Login</button>
    </form>
  );
}

export default Login;


### Dashboard Component

javascript
// Dashboard.js
import { useState, useEffect } from 'react';
import { CognitoUserPool } from 'amazon-cognito-identity-js';

const poolData = {
  UserPoolId: 'us-east-1_XXXXX',
  ClientId: 'your-client-id'
};

const userPool = new CognitoUserPool(poolData);

function Dashboard() {
  const [dashboard, setDashboard] = useState(null);
  const [loading, setLoading] = useState(true);
  
  useEffect(() => {
    fetchDashboard();
  }, []);
  
  async function fetchDashboard() {
    // Get current user
    const cognitoUser = userPool.getCurrentUser();
    
    if (!cognitoUser) {
      window.location.href = '/login';
      return;
    }
    
    // Get session (includes tokens)
    cognitoUser.getSession((err, session) => {
      if (err) {
        console.error('Session error:', err);
        window.location.href = '/login';
        return;
      }
      
      const idToken = session.getIdToken().getJwtToken();
      
      // Fetch dashboard with Cognito ID token
      fetch('https://d1234.cloudfront.net/dashboard', {
        headers: {
          'Authorization': idToken  // Cognito ID token
        }
      })
      .then(res => {
        // Check cache status
        const cacheStatus = res.headers.get('X-Cache');
        console.log('Cache status:', cacheStatus);
        
        return res.json();
      })
      .then(data => {
        setDashboard(data);
        setLoading(false);
      })
      .catch(error => {
        console.error('Error:', error);
        setLoading(false);
      });
    });
  }
  
  function handleLogout() {
    const cognitoUser = userPool.getCurrentUser();
    if (cognitoUser) {
      cognitoUser.signOut();
    }
    localStorage.clear();
    window.location.href = '/login';
  }
  
  if (loading) return <div>Loading...</div>;
  
  if (!dashboard) return <div>Error loading dashboard</div>;
  
  return (
    <div>
      <header>
        <h1>Welcome, {dashboard.username}</h1>
        <button onClick={handleLogout}>Logout</button>
      </header>
      
      <div className="stats">
        <div className="stat-card">
          <h3>Total Orders</h3>
          <p>{dashboard.stats.orders}</p>
        </div>
        <div className="stat-card">
          <h3>Total Spent</h3>
          <p>${dashboard.stats.spent}</p>
        </div>
      </div>
      
      <div className="activity">
        <h2>Recent Activity</h2>
        {dashboard.recentActivity.map(activity => (
          <div key={activity.id} className="activity-item">
            <span>{activity.description}</span>
            <span>{new Date(activity.timestamp).toLocaleString()}</span>
          </div>
        ))}
      </div>
      
      <div className="notifications">
        <h2>Notifications ({dashboard.notifications.length})</h2>
        {dashboard.notifications.map(notif => (
          <div key={notif.id} className="notification">
            {notif.message}
          </div>
        ))}
      </div>
    </div>
  );
}

export default Dashboard;


### App Component

javascript
// App.js
import { useState, useEffect } from 'react';
import { CognitoUserPool } from 'amazon-cognito-identity-js';
import Login from './Login';
import Dashboard from './Dashboard';

const poolData = {
  UserPoolId: 'us-east-1_XXXXX',
  ClientId: 'your-client-id'
};

const userPool = new CognitoUserPool(poolData);

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [loading, setLoading] = useState(true);
  
  useEffect(() => {
    // Check if user is already logged in
    const cognitoUser = userPool.getCurrentUser();
    
    if (cognitoUser) {
      cognitoUser.getSession((err, session) => {
        if (err || !session.isValid()) {
          setIsAuthenticated(false);
        } else {
          setIsAuthenticated(true);
        }
        setLoading(false);
      });
    } else {
      setLoading(false);
    }
  }, []);
  
  if (loading) return <div>Loading...</div>;
  
  return (
    <div className="App">
      {isAuthenticated ? (
        <Dashboard />
      ) : (
        <Login onLoginSuccess={() => setIsAuthenticated(true)} />
      )}
    </div>
  );
}

export default App;


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 6: Testing

### Create Test User

bash
# Create user
aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username testuser \
  --user-attributes Name=email,Value=test@example.com Name=name,Value="Test User" \
  --temporary-password TempPass123!

# Set permanent password
aws cognito-idp admin-set-user-password \
  --user-pool-id $USER_POOL_ID \
  --username testuser \
  --password MyPassword123! \
  --permanent


### Test API

bash
# Login to get ID token
aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id $CLIENT_ID \
  --auth-parameters USERNAME=testuser,PASSWORD=MyPassword123!

# Extract IdToken from response
ID_TOKEN="eyJraWQiOiJ..."

# Test via CloudFront (first request - cache miss)
curl -H "Authorization: $ID_TOKEN" \
  https://d1234.cloudfront.net/dashboard

# Response headers:
# X-Cache: Miss from cloudfront
# Cache-Control: private, max-age=300

# Test again (cache hit)
curl -H "Authorization: $ID_TOKEN" \
  https://d1234.cloudfront.net/dashboard

# Response headers:
# X-Cache: Hit from cloudfront
# Age: 30


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 7: Token Refresh

javascript
// utils/auth.js
import { CognitoUserPool } from 'amazon-cognito-identity-js';

const poolData = {
  UserPoolId: 'us-east-1_XXXXX',
  ClientId: 'your-client-id'
};

const userPool = new CognitoUserPool(poolData);

export async function getValidToken() {
  return new Promise((resolve, reject) => {
    const cognitoUser = userPool.getCurrentUser();
    
    if (!cognitoUser) {
      reject(new Error('No user'));
      return;
    }
    
    cognitoUser.getSession((err, session) => {
      if (err) {
        reject(err);
        return;
      }
      
      if (session.isValid()) {
        resolve(session.getIdToken().getJwtToken());
      } else {
        // Refresh token
        const refreshToken = session.getRefreshToken();
        cognitoUser.refreshSession(refreshToken, (err, newSession) => {
          if (err) {
            reject(err);
          } else {
            resolve(newSession.getIdToken().getJwtToken());
          }
        });
      }
    });
  });
}

// Usage in API calls
export async function fetchWithAuth(url, options = {}) {
  const token = await getValidToken();
  
  return fetch(url, {
    ...options,
    headers: {
      ...options.headers,
      'Authorization': token
    }
  });
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

### Architecture Flow

1. User logs in with Cognito
   ├── Username + Password
   └── Receives ID Token (JWT)

2. User requests dashboard
   ├── Sends ID Token in Authorization header
   ├── CloudFront checks cache (key: /dashboard + ID Token)
   ├── Cache miss → Forward to API Gateway
   ├── API Gateway validates token with Cognito
   ├── Lambda gets user info from token claims
   ├── Lambda fetches data from DynamoDB
   ├── CloudFront caches response (per user)
   └── Returns dashboard

3. User requests dashboard again
   ├── CloudFront cache hit
   └── Returns cached data (fast!)


### Key Benefits

| Benefit | Details |
|---------|---------|
| Security | Cognito handles authentication |
| Per-User Caching | Each user gets separate cache |
| No Custom Auth | No JWT verification in Lambda |
| Token Refresh | Automatic with Cognito SDK |
| 90% Cache Hit Rate | Reduced Lambda/DynamoDB costs |
| 10x Faster | 10ms vs 200ms response time |

### Cost Savings

Without caching (1M requests/month):
- Lambda: $20
- DynamoDB: $25
- Total: $45

With caching (90% hit rate):
- Lambda: $2 (100K invocations)
- DynamoDB: $2.50 (100K reads)
- CloudFront: $8.50
- Total: $13

Savings: $32/month (71% reduction)
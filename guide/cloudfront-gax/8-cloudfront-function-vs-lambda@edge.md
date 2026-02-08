## CloudFront Functions vs Lambda@Edge

### Quick Comparison

| Feature | CloudFront Functions | Lambda@Edge |
|---------|---------------------|-------------|
| Runtime | JavaScript (ECMAScript 5.1) | Node.js, Python |
| Max Duration | <1ms | 5-30 seconds |
| Max Memory | 2 MB | 128-10,240 MB |
| Max Package Size | 10 KB | 1 MB (viewer), 50 MB (origin) |
| Triggers | Viewer request, Viewer response | Viewer request, Viewer response, Origin request, Origin response |
| Network Access | ❌ No | ✅ Yes (HTTP, external APIs) |
| Environment Variables | ❌ No | ✅ Yes |
| Cost | $0.10 per 1M invocations | $0.60 per 1M + duration charges |
| Deployment | Instant | 5-15 minutes |
| Use Case | Simple, fast transformations | Complex logic, external calls |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## CloudFront Functions

### What It Is

Lightweight JavaScript functions that run at CloudFront edge locations

### Characteristics

- Runs in <1ms
- Very limited (2 MB memory, 10 KB code)
- No network access
- JavaScript only (ES5.1)
- Instant deployment
- Very cheap ($0.10 per 1M)

### Use Cases

✅ URL rewrites/redirects
✅ Header manipulation
✅ Request/response modification
✅ A/B testing (simple)
✅ Bot detection (simple)
✅ Cache key normalization

### Example 1: URL Rewrite

javascript
// CloudFront Function
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  
  // Rewrite /products to /products/index.html
  if (uri.endsWith('/')) {
    request.uri += 'index.html';
  } else if (!uri.includes('.')) {
    request.uri += '/index.html';
  }
  
  return request;
}


### Example 2: Add Security Headers

javascript
// CloudFront Function
function handler(event) {
  var response = event.response;
  var headers = response.headers;
  
  // Add security headers
  headers['strict-transport-security'] = { value: 'max-age=31536000; includeSubdomains' };
  headers['x-content-type-options'] = { value: 'nosniff' };
  headers['x-frame-options'] = { value: 'DENY' };
  headers['x-xss-protection'] = { value: '1; mode=block' };
  
  return response;
}


### Example 3: A/B Testing

javascript
// CloudFront Function
function handler(event) {
  var request = event.request;
  var headers = request.headers;
  
  // Get or set A/B test cookie
  var cookies = headers.cookie || { value: '' };
  var cookieValue = cookies.value;
  
  if (!cookieValue.includes('ab_test=')) {
    // Assign user to A or B (50/50)
    var variant = Math.random() < 0.5 ? 'A' : 'B';
    
    // Add cookie to response
    if (!headers['set-cookie']) {
      headers['set-cookie'] = { value: 'ab_test=' + variant + '; Path=/; Max-Age=86400' };
    }
    
    // Route to different origin based on variant
    if (variant === 'B') {
      request.uri = '/beta' + request.uri;
    }
  }
  
  return request;
}


### Deployment

bash
# Create function
aws cloudfront create-function \
  --name url-rewrite \
  --function-config Comment="URL rewrite",Runtime=cloudfront-js-1.0 \
  --function-code fileb://function.js

# Publish function
aws cloudfront publish-function \
  --name url-rewrite \
  --if-match ETVABCDEFG

# Associate with distribution
aws cloudfront update-distribution \
  --id E1234 \
  --distribution-config file://config.json


config.json:
json
{
  "DefaultCacheBehavior": {
    "FunctionAssociations": {
      "Quantity": 1,
      "Items": [{
        "FunctionARN": "arn:aws:cloudfront::ACCOUNT:function/url-rewrite",
        "EventType": "viewer-request"
      }]
    }
  }
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Lambda@Edge

### What It Is

Full Lambda functions that run at CloudFront edge locations

### Characteristics

- Runs up to 30 seconds
- Full Lambda capabilities (128-10,240 MB)
- Network access (HTTP, databases, APIs)
- Node.js or Python
- 5-15 minute deployment
- More expensive ($0.60 per 1M + duration)

### Use Cases

✅ Complex authentication
✅ External API calls
✅ Image resizing
✅ Dynamic content generation
✅ Database queries
✅ JWT validation
✅ Geolocation-based routing

### Example 1: JWT Authentication

javascript
// Lambda@Edge (Node.js)
const jwt = require('jsonwebtoken');

exports.handler = async (event) => {
  const request = event.Records[0].cf.request;
  const headers = request.headers;
  
  // Get Authorization header
  const authHeader = headers.authorization ? headers.authorization[0].value : '';
  
  if (!authHeader) {
    return {
      status: '401',
      statusDescription: 'Unauthorized',
      body: 'Missing authorization header'
    };
  }
  
  try {
    // Verify JWT token
    const token = authHeader.replace('Bearer ', '');
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    
    // Add user info to headers
    headers['x-user-id'] = [{ key: 'X-User-Id', value: decoded.userId }];
    headers['x-username'] = [{ key: 'X-Username', value: decoded.username }];
    
    return request;
    
  } catch (error) {
    return {
      status: '401',
      statusDescription: 'Unauthorized',
      body: 'Invalid token'
    };
  }
};


### Example 2: Image Resizing

javascript
// Lambda@Edge (Node.js)
const AWS = require('aws-sdk');
const sharp = require('sharp');

const s3 = new AWS.S3();

exports.handler = async (event) => {
  const response = event.Records[0].cf.response;
  const request = event.Records[0].cf.request;
  
  // Check if image and resize requested
  const uri = request.uri;
  const params = request.querystring;
  
  if (response.status === '200' && params.includes('width=')) {
    const width = parseInt(params.match(/width=(\d+)/)[1]);
    
    // Get original image from S3
    const s3Object = await s3.getObject({
      Bucket: 'my-images-bucket',
      Key: uri.substring(1)
    }).promise();
    
    // Resize image
    const resizedImage = await sharp(s3Object.Body)
      .resize(width)
      .toBuffer();
    
    // Return resized image
    return {
      status: '200',
      statusDescription: 'OK',
      headers: {
        'content-type': [{ key: 'Content-Type', value: 'image/jpeg' }],
        'cache-control': [{ key: 'Cache-Control', value: 'public, max-age=86400' }]
      },
      body: resizedImage.toString('base64'),
      bodyEncoding: 'base64'
    };
  }
  
  return response;
};


### Example 3: Geolocation Routing

javascript
// Lambda@Edge (Node.js)
exports.handler = async (event) => {
  const request = event.Records[0].cf.request;
  const headers = request.headers;
  
  // Get country from CloudFront header
  const country = headers['cloudfront-viewer-country'] 
    ? headers['cloudfront-viewer-country'][0].value 
    : 'US';
  
  // Route to region-specific origin
  if (['CN', 'JP', 'KR'].includes(country)) {
    request.origin = {
      custom: {
        domainName: 'asia.example.com',
        port: 443,
        protocol: 'https',
        path: '',
        sslProtocols: ['TLSv1.2'],
        readTimeout: 30,
        keepaliveTimeout: 5
      }
    };
  } else if (['GB', 'FR', 'DE'].includes(country)) {
    request.origin = {
      custom: {
        domainName: 'europe.example.com',
        port: 443,
        protocol: 'https',
        path: '',
        sslProtocols: ['TLSv1.2'],
        readTimeout: 30,
        keepaliveTimeout: 5
      }
    };
  }
  
  return request;
};


### Deployment

bash
# Create Lambda function in us-east-1 (required for Lambda@Edge)
aws lambda create-function \
  --region us-east-1 \
  --function-name jwt-auth-edge \
  --runtime nodejs18.x \
  --role arn:aws:iam::ACCOUNT:role/lambda-edge-role \
  --handler index.handler \
  --zip-file fileb://function.zip

# Publish version
VERSION=$(aws lambda publish-version \
  --region us-east-1 \
  --function-name jwt-auth-edge \
  --query 'Version' \
  --output text)

# Associate with CloudFront
aws cloudfront update-distribution \
  --id E1234 \
  --distribution-config file://config.json


config.json:
json
{
  "DefaultCacheBehavior": {
    "LambdaFunctionAssociations": {
      "Quantity": 1,
      "Items": [{
        "LambdaFunctionARN": "arn:aws:lambda:us-east-1:ACCOUNT:function:jwt-auth-edge:VERSION",
        "EventType": "viewer-request",
        "IncludeBody": false
      }]
    }
  }
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Trigger Points

### CloudFront Functions (2 triggers)

Client → [Viewer Request] → CloudFront → Origin
Client ← [Viewer Response] ← CloudFront ← Origin


### Lambda@Edge (4 triggers)

Client → [Viewer Request] → CloudFront → [Origin Request] → Origin
Client ← [Viewer Response] ← CloudFront ← [Origin Response] ← Origin


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Comparison

### CloudFront Functions

Price: $0.10 per 1 million invocations

Example (10 million requests/month):
Cost: (10M / 1M) × $0.10 = $1.00/month


### Lambda@Edge

Price:
- $0.60 per 1 million requests
- $0.00005001 per GB-second

Example (10 million requests/month, 128 MB, 50ms avg):
- Requests: (10M / 1M) × $0.60 = $6.00
- Duration: 10M × 0.05s × 0.125GB × $0.00005001 = $3.13
Total: $9.13/month

9x more expensive than CloudFront Functions!


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Limitations

### CloudFront Functions

| Limitation | Value |
|------------|-------|
| Max execution time | <1ms |
| Max memory | 2 MB |
| Max code size | 10 KB |
| Network access | ❌ No |
| File system access | ❌ No |
| Environment variables | ❌ No |
| External libraries | ❌ No (except built-in) |
| Language | JavaScript (ES5.1) only |

### Lambda@Edge

| Limitation | Value |
|------------|-------|
| Max execution time | 5s (viewer), 30s (origin) |
| Max memory | 128-10,240 MB |
| Max code size | 1 MB (viewer), 50 MB (origin) |
| Network access | ✅ Yes |
| File system access | ❌ No /tmp |
| Environment variables | ✅ Yes |
| External libraries | ✅ Yes |
| Language | Node.js, Python |
| Deployment region | us-east-1 only |
| Deployment time | 5-15 minutes |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Decision Matrix

### Use CloudFront Functions When:

✅ Simple logic (<10 KB code)
✅ Fast execution (<1ms)
✅ No external calls needed
✅ URL rewrites/redirects
✅ Header manipulation
✅ Cache key normalization
✅ Cost-sensitive
✅ Need instant deployment

### Use Lambda@Edge When:

✅ Complex logic (>10 KB code)
✅ Need external API calls
✅ Database queries
✅ Image processing
✅ JWT validation with external libraries
✅ Need Node.js/Python features
✅ Need environment variables
✅ Execution time >1ms

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Example: Both Together

### CloudFront Functions (Viewer Request)

javascript
// Fast URL normalization
function handler(event) {
  var request = event.request;
  
  // Normalize URL
  request.uri = request.uri.toLowerCase();
  
  // Remove trailing slash
  if (request.uri.endsWith('/') && request.uri !== '/') {
    request.uri = request.uri.slice(0, -1);
  }
  
  return request;
}


### Lambda@Edge (Origin Request)

javascript
// Complex authentication
const jwt = require('jsonwebtoken');
const axios = require('axios');

exports.handler = async (event) => {
  const request = event.Records[0].cf.request;
  
  // Verify JWT
  const token = request.headers.authorization[0].value.replace('Bearer ', '');
  const decoded = jwt.verify(token, process.env.JWT_SECRET);
  
  // Check user permissions from external API
  const permissions = await axios.get(`https://api.example.com/users/${decoded.userId}/permissions`);
  
  if (!permissions.data.canAccess) {
    return {
      status: '403',
      body: 'Forbidden'
    };
  }
  
  return request;
};


### Configuration

json
{
  "DefaultCacheBehavior": {
    "FunctionAssociations": {
      "Quantity": 1,
      "Items": [{
        "FunctionARN": "arn:aws:cloudfront::ACCOUNT:function/url-normalize",
        "EventType": "viewer-request"
      }]
    },
    "LambdaFunctionAssociations": {
      "Quantity": 1,
      "Items": [{
        "LambdaFunctionARN": "arn:aws:lambda:us-east-1:ACCOUNT:function:auth:1",
        "EventType": "origin-request"
      }]
    }
  }
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

| Use Case | Choose |
|----------|--------|
| URL rewrite | CloudFront Functions |
| Add headers | CloudFront Functions |
| A/B testing (simple) | CloudFront Functions |
| JWT validation | Lambda@Edge |
| External API calls | Lambda@Edge |
| Image resizing | Lambda@Edge |
| Database queries | Lambda@Edge |
| Geolocation routing | Lambda@Edge |
| Bot detection (simple) | CloudFront Functions |
| Bot detection (complex) | Lambda@Edge |

Rule of thumb:
- **CloudFront Functions** = Fast, simple, cheap (90% of use cases)
- **Lambda@Edge** = Complex, powerful, expensive (10% of use cases)

Cost difference: CloudFront Functions are 9x cheaper than Lambda@Edge for same number of requests.
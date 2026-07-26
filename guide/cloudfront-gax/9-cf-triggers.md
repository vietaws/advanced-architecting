## CloudFront Function and Lambda@Edge Triggers

### Trigger Points Overview

Client → [1. Viewer Request] → CloudFront Cache → [2. Origin Request] → Origin
Client ← [4. Viewer Response] ← CloudFront Cache ← [3. Origin Response] ← Origin

CloudFront Functions: Triggers 1, 4
Lambda@Edge: Triggers 1, 2, 3, 4


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## CloudFront Functions Triggers

### 1. Viewer Request (CloudFront Function)

When: Before CloudFront checks cache
Use: Modify request before cache lookup

javascript
// Example: URL Rewrite
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  
  // Rewrite /old-path to /new-path
  if (uri.startsWith('/old-path')) {
    request.uri = uri.replace('/old-path', '/new-path');
  }
  
  // Add index.html to directories
  if (uri.endsWith('/')) {
    request.uri += 'index.html';
  }
  
  return request;
}


Flow:
User requests: /products/
↓
Viewer Request Function: Rewrites to /products/index.html
↓
CloudFront checks cache for /products/index.html


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 2. Viewer Response (CloudFront Function)

When: Before CloudFront returns response to client
Use: Modify response headers

javascript
// Example: Add Security Headers
function handler(event) {
  var response = event.response;
  var headers = response.headers;
  
  // Add security headers
  headers['strict-transport-security'] = { 
    value: 'max-age=31536000; includeSubdomains; preload' 
  };
  headers['x-content-type-options'] = { 
    value: 'nosniff' 
  };
  headers['x-frame-options'] = { 
    value: 'DENY' 
  };
  headers['x-xss-protection'] = { 
    value: '1; mode=block' 
  };
  headers['referrer-policy'] = { 
    value: 'strict-origin-when-cross-origin' 
  };
  
  return response;
}


Flow:
CloudFront has response (from cache or origin)
↓
Viewer Response Function: Adds security headers
↓
Response sent to user with added headers


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Lambda@Edge Triggers

### 1. Viewer Request (Lambda@Edge)

When: Before CloudFront checks cache
Use: Authentication, complex request modification

javascript
// Example: JWT Authentication
const jwt = require('jsonwebtoken');

exports.handler = async (event) => {
  const request = event.Records[0].cf.request;
  const headers = request.headers;
  
  // Check for Authorization header
  if (!headers.authorization) {
    return {
      status: '401',
      statusDescription: 'Unauthorized',
      headers: {
        'www-authenticate': [{ key: 'WWW-Authenticate', value: 'Bearer' }]
      },
      body: 'Authorization required'
    };
  }
  
  try {
    // Verify JWT
    const token = headers.authorization[0].value.replace('Bearer ', '');
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    
    // Add user info to headers for origin
    headers['x-user-id'] = [{ key: 'X-User-Id', value: decoded.userId }];
    headers['x-user-role'] = [{ key: 'X-User-Role', value: decoded.role }];
    
    return request;
    
  } catch (error) {
    return {
      status: '401',
      statusDescription: 'Unauthorized',
      body: 'Invalid token'
    };
  }
};


Flow:
User requests: /api/dashboard
↓
Viewer Request Lambda: Validates JWT token
↓
If valid: Continue to cache check
If invalid: Return 401 immediately


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 2. Origin Request (Lambda@Edge)

When: After cache miss, before request goes to origin
Use: Modify request to origin, add authentication

javascript
// Example: Add Origin Authentication
exports.handler = async (event) => {
  const request = event.Records[0].cf.request;
  
  // Add authentication header for origin
  request.headers['x-origin-secret'] = [{
    key: 'X-Origin-Secret',
    value: process.env.ORIGIN_SECRET
  }];
  
  // Add custom headers
  request.headers['x-cloudfront-request'] = [{
    key: 'X-CloudFront-Request',
    value: 'true'
  }];
  
  // Modify origin based on path
  if (request.uri.startsWith('/api/')) {
    request.origin = {
      custom: {
        domainName: 'api.example.com',
        port: 443,
        protocol: 'https',
        path: '/v1',
        sslProtocols: ['TLSv1.2'],
        readTimeout: 30,
        keepaliveTimeout: 5
      }
    };
  }
  
  return request;
};


Flow:
Cache miss for /api/users
↓
Origin Request Lambda: Adds authentication, modifies origin
↓
Request sent to api.example.com/v1/api/users with auth header


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 3. Origin Response (Lambda@Edge)

When: After origin returns response, before caching
Use: Modify response, generate content, image processing

javascript
// Example: Image Resizing
const AWS = require('aws-sdk');
const sharp = require('sharp');

const s3 = new AWS.S3();

exports.handler = async (event) => {
  const response = event.Records[0].cf.response;
  const request = event.Records[0].cf.request;
  
  // Check if image and resize requested
  const uri = request.uri;
  const width = request.querystring.match(/width=(\d+)/);
  
  if (response.status === '200' && width && uri.match(/\.(jpg|jpeg|png)$/)) {
    const widthValue = parseInt(width[1]);
    
    // Get image body
    const body = Buffer.from(response.body, 'base64');
    
    // Resize image
    const resizedImage = await sharp(body)
      .resize(widthValue)
      .toBuffer();
    
    // Update response
    response.body = resizedImage.toString('base64');
    response.bodyEncoding = 'base64';
    response.headers['content-length'] = [{
      key: 'Content-Length',
      value: resizedImage.length.toString()
    }];
    response.headers['cache-control'] = [{
      key: 'Cache-Control',
      value: 'public, max-age=86400'
    }];
  }
  
  return response;
};


Flow:
Origin returns image.jpg
↓
Origin Response Lambda: Resizes image based on ?width=300
↓
Resized image cached in CloudFront
↓
Future requests get resized version from cache


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 4. Viewer Response (Lambda@Edge)

When: Before CloudFront returns response to client
Use: Complex response modification, A/B testing

javascript
// Example: A/B Testing with Cookie
exports.handler = async (event) => {
  const request = event.Records[0].cf.request;
  const response = event.Records[0].cf.response;
  
  // Check if user has A/B test cookie
  const cookies = request.headers.cookie || [];
  let hasTestCookie = false;
  
  for (let cookie of cookies) {
    if (cookie.value.includes('ab_test=')) {
      hasTestCookie = true;
      break;
    }
  }
  
  // Assign variant if no cookie
  if (!hasTestCookie) {
    const variant = Math.random() < 0.5 ? 'A' : 'B';
    
    // Set cookie
    response.headers['set-cookie'] = [{
      key: 'Set-Cookie',
      value: `ab_test=${variant}; Path=/; Max-Age=2592000; Secure; HttpOnly`
    }];
    
    // Add variant header for analytics
    response.headers['x-ab-variant'] = [{
      key: 'X-AB-Variant',
      value: variant
    }];
  }
  
  return response;
};


Flow:
CloudFront has response ready
↓
Viewer Response Lambda: Checks for A/B test cookie
↓
If missing: Assigns variant, sets cookie
↓
Response sent to user with cookie


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Example: All Triggers Together

### Use Case: Authenticated API with Image Resizing

User Request: GET /images/photo.jpg?width=300
Authorization: Bearer abc123


### 1. Viewer Request (Lambda@Edge)

javascript
// Validate JWT token
exports.handler = async (event) => {
  const request = event.Records[0].cf.request;
  const token = request.headers.authorization[0].value.replace('Bearer ', '');
  
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    request.headers['x-user-id'] = [{ key: 'X-User-Id', value: decoded.userId }];
    return request;
  } catch (error) {
    return { status: '401', body: 'Unauthorized' };
  }
};


Result: Token validated, user ID added to headers

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 2. CloudFront Cache Check

Cache key: /images/photo.jpg?width=300
Result: Cache miss (first request for this size)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 3. Origin Request (Lambda@Edge)

javascript
// Add authentication for S3
exports.handler = async (event) => {
  const request = event.Records[0].cf.request;
  
  // Change origin to S3
  request.origin = {
    s3: {
      domainName: 'my-images.s3.amazonaws.com',
      region: 'us-east-1',
      authMethod: 'origin-access-identity',
      path: ''
    }
  };
  
  // Remove query string (S3 doesn't need it)
  request.querystring = '';
  
  return request;
};


Result: Request sent to S3 for original image

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 4. Origin Response (Lambda@Edge)

javascript
// Resize image
const sharp = require('sharp');

exports.handler = async (event) => {
  const response = event.Records[0].cf.response;
  const request = event.Records[0].cf.request;
  
  // Get width from original query string
  const width = 300;  // Parsed from original request
  
  // Resize image
  const body = Buffer.from(response.body, 'base64');
  const resized = await sharp(body).resize(width).toBuffer();
  
  response.body = resized.toString('base64');
  response.bodyEncoding = 'base64';
  response.headers['cache-control'] = [{
    key: 'Cache-Control',
    value: 'public, max-age=86400'
  }];
  
  return response;
};


Result: Image resized to 300px width

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 5. CloudFront Caches Response

Cache key: /images/photo.jpg?width=300
Cached: Resized image (300px)
TTL: 86400 seconds (24 hours)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 6. Viewer Response (CloudFront Function)

javascript
// Add security headers
function handler(event) {
  var response = event.response;
  
  response.headers['x-content-type-options'] = { value: 'nosniff' };
  response.headers['x-frame-options'] = { value: 'DENY' };
  
  return response;
}


Result: Security headers added to response

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 7. Response to User

HTTP/1.1 200 OK
Content-Type: image/jpeg
Cache-Control: public, max-age=86400
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-Cache: Miss from cloudfront

[Resized image data]


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Trigger Comparison

| Trigger | CloudFront Function | Lambda@Edge | Use Case |
|---------|---------------------|-------------|----------|
| Viewer Request | ✅ Yes | ✅ Yes | URL rewrite (CF), Auth (Lambda) |
| Origin Request | ❌ No | ✅ Yes | Modify origin, add auth |
| Origin Response | ❌ No | ✅ Yes | Image resize, content generation |
| Viewer Response | ✅ Yes | ✅ Yes | Add headers (CF), A/B test (Lambda) |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

### CloudFront Functions (2 triggers)

Viewer Request:
- URL rewrites
- Header normalization
- Simple redirects

Viewer Response:
- Add security headers
- Remove headers
- Simple modifications

### Lambda@Edge (4 triggers)

Viewer Request:
- JWT authentication
- Complex authorization
- Bot detection

Origin Request:
- Change origin dynamically
- Add authentication headers
- Modify request to origin

Origin Response:
- Image resizing
- Content generation
- Response transformation

Viewer Response:
- A/B testing with cookies
- Complex header logic
- Analytics tracking

Key Point: Use CloudFront Functions for simple/fast operations, Lambda@Edge for complex logic or when you need Origin Request/
Response triggers.
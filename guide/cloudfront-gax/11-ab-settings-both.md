## A/B Testing: CloudFront Functions vs Lambda@Edge

### Architecture

Users → CloudFront → ALB → EC2 Auto Scaling Group

Option A: A/B at CloudFront Function (Viewer Request/Response)
Option B: A/B at Lambda@Edge (Origin Request/Response)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Option A: A/B Testing with CloudFront Function

### How It Works

User Request
  ↓
CloudFront Function (Viewer Request)
  → Read cookie
  → If no cookie, assign variant randomly
  → Add variant header to request
  → Modify cache key to include variant
  ↓
CloudFront Cache (separate cache per variant)
  ↓ (cache miss)
ALB → EC2 (reads X-AB-Variant header)
  ↓
CloudFront Function (Viewer Response)
  → Set cookie on response
  ↓
User receives response


### Viewer Request Function

javascript
// cf-func-ab-viewer-request.js
function handler(event) {
    var request = event.request;
    var cookies = request.cookies;
    var variant = 'A';

    // Check existing cookie
    if (cookies['ab-variant'] && cookies['ab-variant'].value) {
        variant = cookies['ab-variant'].value;
    } else {
        // Assign randomly using simple hash of viewer IP
        var ip = event.viewer.ip;
        var hash = 0;
        for (var i = 0; i < ip.length; i++) {
            hash = ((hash << 5) - hash) + ip.charCodeAt(i);
            hash |= 0;
        }
        variant = (Math.abs(hash) % 100) < 50 ? 'A' : 'B';
    }

    // Add header for origin to read
    request.headers['x-ab-variant'] = { value: variant };

    // IMPORTANT: Add to cache key so A and B get separate caches
    request.headers['x-ab-cache-key'] = { value: variant };

    return request;
}


### Viewer Response Function

javascript
// cf-func-ab-viewer-response.js
function handler(event) {
    var response = event.response;
    var request = event.request;
    var variant = request.headers['x-ab-variant'] ? request.headers['x-ab-variant'].value : 'A';

    // Set cookie if not present
    if (!request.cookies['ab-variant']) {
        response.cookies['ab-variant'] = {
            value: variant,
            attributes: 'Path=/; Max-Age=86400; Secure; HttpOnly'
        };
    }

    // Add debug header
    response.headers['x-ab-variant'] = { value: variant };

    return response;
}


### CloudFront Cache Policy (include variant in cache key)

bash
CACHE_POLICY_ID=$(aws cloudfront create-cache-policy \
  --cache-policy-config '{
    "Name": "AB-Test-Cache-Policy",
    "DefaultTTL": 86400,
    "MaxTTL": 31536000,
    "MinTTL": 0,
    "ParametersInCacheKeyAndForwardedToOrigin": {
      "EnableAcceptEncodingGzip": true,
      "EnableAcceptEncodingBrotli": true,
      "HeadersConfig": {
        "HeaderBehavior": "whitelist",
        "Headers": {
          "Quantity": 1,
          "Items": ["x-ab-cache-key"]
        }
      },
      "CookiesConfig": { "CookieBehavior": "none" },
      "QueryStringsConfig": { "QueryStringBehavior": "none" }
    }
  }' \
  --query 'CachePolicy.Id' --output text)


### Deploy CloudFront Functions

bash
aws cloudfront create-function \
  --name ab-viewer-request \
  --function-config Comment="A/B viewer request",Runtime=cloudfront-js-2.0 \
  --function-code fileb://cf-func-ab-viewer-request.js

ETAG=$(aws cloudfront describe-function --name ab-viewer-request --query 'ETag' --output text)
aws cloudfront publish-function --name ab-viewer-request --if-match $ETAG

CF_AB_REQ=$(aws cloudfront describe-function --name ab-viewer-request \
  --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)

aws cloudfront create-function \
  --name ab-viewer-response \
  --function-config Comment="A/B viewer response",Runtime=cloudfront-js-2.0 \
  --function-code fileb://cf-func-ab-viewer-response.js

ETAG=$(aws cloudfront describe-function --name ab-viewer-response --query 'ETag' --output text)
aws cloudfront publish-function --name ab-viewer-response --if-match $ETAG

CF_AB_RESP=$(aws cloudfront describe-function --name ab-viewer-response \
  --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)


### Limitations

- **No network access** - Can't call external services for variant config
- **No Math.random()** - Must use deterministic hashing (viewer IP, request ID)
- **1ms execution limit** - Can't do complex logic
- **10KB package limit** - Can't embed large routing tables
- **No request body access** - Can't route based on POST data

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Option B: A/B Testing with Lambda@Edge

### How It Works

User Request
  ↓
CloudFront (Viewer layer - no function)
  ↓
CloudFront Cache
  ↓ (cache miss)
Lambda@Edge (Origin Request)
  → Read cookie
  → If no cookie, assign variant (can use Math.random, external config)
  → Can change origin (different ALB/server per variant)
  → Can modify request path, headers, body
  ↓
ALB → EC2 (reads variant header)
  ↓
Lambda@Edge (Origin Response)
  → Set cookie
  → Modify response headers/body
  → Can call external services (analytics, logging)
  ↓
CloudFront caches response
  ↓
User receives response


### Origin Request Function

javascript
// lambda-ab-origin-request.js
'use strict';

// Can use external config, feature flags, weighted distribution
const VARIANT_CONFIG = {
    weights: { A: 70, B: 30 },  // 70/30 split
    enabled: true
};

exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    const cookies = request.headers.cookie || [];
    let variant = null;

    // Check existing cookie
    for (const c of cookies) {
        const match = c.value.match(/ab-variant=([AB])/);
        if (match) { variant = match[1]; break; }
    }

    // Assign variant based on weighted distribution
    if (!variant) {
        const rand = Math.random() * 100;
        variant = rand < VARIANT_CONFIG.weights.A ? 'A' : 'B';
    }

    // Add header for origin
    request.headers['x-ab-variant'] = [{ key: 'X-AB-Variant', value: variant }];

    // OPTION: Change origin based on variant (different ALB/server)
    // if (variant === 'B') {
    //     request.origin.custom.domainName = 'alb-variant-b.example.com';
    //     request.headers['host'] = [{ key: 'host', value: 'alb-variant-b.example.com' }];
    // }

    // OPTION: Change request path based on variant
    // if (variant === 'B') {
    //     request.uri = request.uri.replace(/^\//, '/v2/');
    // }

    return request;
};


### Origin Response Function

javascript
// lambda-ab-origin-response.js
'use strict';

exports.handler = async (event) => {
    const response = event.Records[0].cf.response;
    const request = event.Records[0].cf.request;
    const variant = request.headers['x-ab-variant']
        ? request.headers['x-ab-variant'][0].value : 'A';

    // Set cookie
    const existingCookies = response.headers['set-cookie'] || [];
    existingCookies.push({
        key: 'Set-Cookie',
        value: `ab-variant=${variant}; Path=/; Max-Age=86400; Secure; HttpOnly`
    });
    response.headers['set-cookie'] = existingCookies;

    // Debug header
    response.headers['x-ab-variant'] = [{ key: 'X-AB-Variant', value: variant }];

    return response;
};


### Deploy Lambda@Edge

bash
# IAM Role
cat > lambda-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
    },
    "Action": "sts:AssumeRole"
  }]
}
EOF

ROLE_ARN=$(aws iam create-role \
  --role-name lambda-edge-ab-role \
  --assume-role-policy-document file://lambda-trust.json \
  --query 'Role.Arn' --output text)

aws iam attach-role-policy \
  --role-name lambda-edge-ab-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

sleep 10

# Deploy Origin Request
zip lambda-ab-origin-request.zip lambda-ab-origin-request.js
LAMBDA_OR_ARN=$(aws lambda create-function \
  --function-name ab-origin-request \
  --runtime nodejs18.x \
  --role $ROLE_ARN \
  --handler lambda-ab-origin-request.handler \
  --zip-file fileb://lambda-ab-origin-request.zip \
  --memory-size 128 --timeout 5 \
  --region us-east-1 \
  --query 'FunctionArn' --output text)

LAMBDA_OR_VER=$(aws lambda publish-version \
  --function-name ab-origin-request --region us-east-1 \
  --query 'Version' --output text)

# Deploy Origin Response
zip lambda-ab-origin-response.zip lambda-ab-origin-response.js
LAMBDA_ORESP_ARN=$(aws lambda create-function \
  --function-name ab-origin-response \
  --runtime nodejs18.x \
  --role $ROLE_ARN \
  --handler lambda-ab-origin-response.handler \
  --zip-file fileb://lambda-ab-origin-response.zip \
  --memory-size 128 --timeout 5 \
  --region us-east-1 \
  --query 'FunctionArn' --output text)

LAMBDA_ORESP_VER=$(aws lambda publish-version \
  --function-name ab-origin-response --region us-east-1 \
  --query 'Version' --output text)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Key Differences

### Execution Point

CloudFront Function:                Lambda@Edge:
                                    
User ──→ [CF Function] ──→ Cache    User ──→ Cache ──→ [Lambda@Edge] ──→ Origin
         Viewer Request              (cache miss only)  Origin Request
         
         Runs on EVERY request       Runs only on CACHE MISSES


This is the most critical difference:

| Aspect | CloudFront Function | Lambda@Edge |
|--------|-------------------|-------------|
| When it runs | Every request (before cache) | Only on cache misses (after cache) |
| Variant assignment | Every user gets assigned immediately | Only assigned when cache misses |
| Cache behavior | Must include variant in cache key | Can use single cache with origin-side logic |

### Detailed Comparison

| Feature | CF Function (Viewer) | Lambda@Edge (Origin) |
|---------|---------------------|---------------------|
| Trigger frequency | Every request | Cache misses only |
| Latency added | <1ms | 5-50ms |
| Math.random() | Not available | Available |
| Network calls | Not possible | Can call DynamoDB, S3, APIs |
| Change origin | Not possible | Can switch ALB/origin per variant |
| Modify request path | Yes (simple) | Yes (complex logic) |
| Read request body | No | Yes |
| Max execution | 1ms | 30s (origin trigger) |
| Cost per 1M requests | $0.10 | $0.60 + duration |
| Deploy speed | Seconds | Minutes (global replication) |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Caching Implications

### CloudFront Function Approach

Request A (variant=A) → CF Function adds x-ab-cache-key=A → Cache Key: /page|A
Request B (variant=B) → CF Function adds x-ab-cache-key=B → Cache Key: /page|B

Result: 2 cached copies per page
Cache hit ratio: Lower (split cache)


### Lambda@Edge Approach

Option 1: No cache split (dynamic content)
Request → Cache MISS → Lambda@Edge assigns variant → Origin returns personalized content
TTL=0 or short TTL

Result: Every request hits origin
Cache hit ratio: 0% (no caching)


Option 2: Cache split via origin response
Request → Cache MISS → Lambda@Edge assigns variant → Origin returns content
→ Lambda@Edge adds Vary: X-AB-Variant header
→ CloudFront caches per variant

Result: Similar to CF Function but Lambda only runs on cache miss
Cache hit ratio: Higher (Lambda doesn't run on cache hits)


Option 3: Change origin per variant
Variant A → Lambda@Edge routes to ALB-A (blue deployment)
Variant B → Lambda@Edge routes to ALB-B (green deployment)

Result: Completely separate backends
Cache hit ratio: Normal per origin


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Real-World Scenarios

### Scenario 1: Simple UI A/B Test (Use CloudFront Function)

Goal: Show different button colors to users

CF Function sets cookie → Adds variant header → 
EC2 reads header → Returns different CSS

Best fit: CloudFront Function
Why: Simple, fast, cheap, no external calls needed


### Scenario 2: Feature Flag with Remote Config (Use Lambda@Edge)

Goal: Enable new feature for 30% of users, config stored in DynamoDB

javascript
// Lambda@Edge can call DynamoDB
const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient({ region: 'us-east-1' });

exports.handler = async (event) => {
    const request = event.Records[0].cf.request;

    // Fetch config from DynamoDB
    const config = await dynamodb.get({
        TableName: 'ab-test-config',
        Key: { testId: 'homepage-redesign' }
    }).promise();

    const weight = config.Item.variantBWeight; // e.g., 30
    const variant = Math.random() * 100 < weight ? 'B' : 'A';

    request.headers['x-ab-variant'] = [{ key: 'X-AB-Variant', value: variant }];
    return request;
};


Not possible with CF Function - no network access, no SDK.

### Scenario 3: Blue/Green Deployment (Use Lambda@Edge)

Goal: Route 10% traffic to new version on different ALB

javascript
exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    const cookies = request.headers.cookie || [];
    let variant = Math.random() < 0.1 ? 'B' : 'A';

    for (const c of cookies) {
        const match = c.value.match(/deploy-variant=([AB])/);
        if (match) { variant = match[1]; break; }
    }

    if (variant === 'B') {
        // Route to new ALB
        request.origin.custom.domainName = 'alb-v2.example.com';
        request.headers['host'] = [{ key: 'host', value: 'alb-v2.example.com' }];
    }

    request.headers['x-deploy-variant'] = [{ key: 'X-Deploy-Variant', value: variant }];
    return request;
};


Not possible with CF Function - can't change origin.

### Scenario 4: Geo-Based A/B Test (Both Work)

CloudFront Function:
javascript
function handler(event) {
    var request = event.request;
    var country = event.viewer.country || 'US';
    // Route US to variant A, others to B
    var variant = (country === 'US') ? 'A' : 'B';
    request.headers['x-ab-variant'] = { value: variant };
    return request;
}


Lambda@Edge:
javascript
exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    const country = request.headers['cloudfront-viewer-country']
        ? request.headers['cloudfront-viewer-country'][0].value : 'US';
    const variant = country === 'US' ? 'A' : 'B';
    request.headers['x-ab-variant'] = [{ key: 'X-AB-Variant', value: variant }];
    return request;
};


Recommendation: Use CF Function - cheaper, faster, sufficient for this use case.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Comparison at Scale

### Assumptions: 10M requests/day, 30% cache hit ratio

CloudFront Function (runs on every request):
Invocations: 10M/day × 30 = 300M/month
Cost: 300M × $0.10/M = $30.00/month


Lambda@Edge (runs on cache misses only):
Cache misses: 10M × 0.7 = 7M/day × 30 = 210M/month
Cost: 210M × $0.60/M = $126.00/month
+ Duration: 210M × 5ms × 128MB / 1024 × $0.00005001/GB-s = $6.43/month
Total: $132.43/month


But with higher cache hit ratio (80%):
CF Function: Still 300M × $0.10/M = $30.00/month (runs every request)
Lambda@Edge: 60M × $0.60/M + duration = $39.81/month


| Cache Hit Ratio | CF Function Cost | Lambda@Edge Cost | Winner |
|-----------------|-----------------|-----------------|--------|
| 0% (no cache) | $30.00 | $192.04 | CF Function |
| 30% | $30.00 | $132.43 | CF Function |
| 50% | $30.00 | $96.02 | CF Function |
| 80% | $30.00 | $39.81 | CF Function |
| 95% | $30.00 | $12.63 | Lambda@Edge |
| 99% | $30.00 | $5.05 | Lambda@Edge |

Takeaway: Lambda@Edge is cheaper only when cache hit ratio is >90% because it only runs on cache misses. But if you need its 
capabilities (network access, origin switching), the extra cost is justified.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Decision Matrix

Need to change origin per variant?
  → YES → Lambda@Edge (only option)
  → NO ↓

Need external config (DynamoDB, API)?
  → YES → Lambda@Edge (only option)
  → NO ↓

Need Math.random() for true randomness?
  → YES → Lambda@Edge
  → NO (deterministic hash OK) ↓

Need request body access?
  → YES → Lambda@Edge
  → NO ↓

Cache hit ratio > 90%?
  → YES → Lambda@Edge (cheaper)
  → NO → CloudFront Function (cheaper + faster)


### Recommendation

For most A/B testing scenarios, start with CloudFront Functions. Upgrade to Lambda@Edge only when you need:
- Dynamic origin switching (blue/green)
- External configuration (feature flags from DynamoDB)
- Complex weighted distribution with true randomness
- Request body inspection
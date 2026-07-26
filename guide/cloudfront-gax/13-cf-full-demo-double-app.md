## Origin Switching: CloudFront Function vs Lambda@Edge

### Short Answer

You must use Lambda@Edge. CloudFront Functions cannot change the origin.

| Capability | CloudFront Function | Lambda@Edge |
|-----------|-------------------|-------------|
| Change origin | ❌ Not possible | ✅ Origin Request trigger |
| Modify request headers | ✅ | ✅ |
| Modify request URI/path | ✅ | ✅ |

CloudFront Functions only run at the Viewer level. Origin selection happens after the cache layer, which only Lambda@Edge (
Origin Request) can intercept.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Architecture

Users → CloudFront Distribution
          │
          ├── Origin 1: ALB-V1 (current production)
          ├── Origin 2: ALB-V2 (new version)
          │
          └── Lambda@Edge (Origin Request)
                → Reads cookie / weight config
                → Switches request.origin to ALB-V1 or ALB-V2


### However - There's a Hybrid Approach

You can combine both:

Users → CloudFront
          │
          ├── CF Function (Viewer Request)
          │     → Assign variant cookie (fast, cheap, every request)
          │     → Add variant header
          │
          ├── Lambda@Edge (Origin Request) 
          │     → Read variant header
          │     → Switch origin to ALB-V1 or ALB-V2
          │
          └── CF Function (Viewer Response)
                → Set cookie for sticky sessions


Why hybrid? CF Function handles the cheap/fast part (cookie logic on every request), Lambda@Edge handles what only it can do (
origin switching on cache misses).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Option 1: Lambda@Edge Only (Simple)

### Setup Origins

bash
# Assume you have:
# ALB_V1_DNS = alb-v1-xxxx.ap-southeast-1.elb.amazonaws.com
# ALB_V2_DNS = alb-v2-xxxx.ap-southeast-1.elb.amazonaws.com

# Distribution with both origins
cat > dist-config.json << EOF
{
  "CallerReference": "$(date +%s)",
  "Comment": "Blue/Green with Lambda@Edge",
  "Enabled": true,
  "PriceClass": "PriceClass_100",
  "Origins": {
    "Quantity": 2,
    "Items": [
      {
        "Id": "ALB-V1",
        "DomainName": "${ALB_V1_DNS}",
        "CustomOriginConfig": {
          "HTTPPort": 80, "HTTPSPort": 443,
          "OriginProtocolPolicy": "http-only",
          "OriginSslProtocols": { "Quantity": 1, "Items": ["TLSv1.2"] }
        }
      },
      {
        "Id": "ALB-V2",
        "DomainName": "${ALB_V2_DNS}",
        "CustomOriginConfig": {
          "HTTPPort": 80, "HTTPSPort": 443,
          "OriginProtocolPolicy": "http-only",
          "OriginSslProtocols": { "Quantity": 1, "Items": ["TLSv1.2"] }
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "ALB-V1",
    ...
  }
}
EOF


### Lambda@Edge - Origin Request

javascript
// lambda-origin-switch.js
'use strict';

const defined_origins = {
    'V1': 'alb-v1-xxxx.ap-southeast-1.elb.amazonaws.com',
    'V2': 'alb-v2-xxxx.ap-southeast-1.elb.amazonaws.com'
};

// Weight: percentage routed to V2
const V2_WEIGHT = 10; // 10% to V2

exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    const cookies = request.headers.cookie || [];

    // Check existing cookie
    let version = null;
    for (const c of cookies) {
        const match = c.value.match(/app-version=(V[12])/);
        if (match) { version = match[1]; break; }
    }

    // Assign if no cookie
    if (!version) {
        version = (Math.random() * 100) < V2_WEIGHT ? 'V2' : 'V1';
    }

    // Switch origin
    const targetDomain = defined_origins[version];
    request.origin.custom.domainName = targetDomain;
    request.headers['host'] = [{ key: 'host', value: targetDomain }];

    // Pass version to origin response for cookie setting
    request.headers['x-app-version'] = [{ key: 'X-App-Version', value: version }];

    return request;
};


### Lambda@Edge - Origin Response (set cookie)

javascript
// lambda-origin-switch-response.js
'use strict';

exports.handler = async (event) => {
    const response = event.Records[0].cf.response;
    const request = event.Records[0].cf.request;
    const version = request.headers['x-app-version']
        ? request.headers['x-app-version'][0].value : 'V1';

    const existing = response.headers['set-cookie'] || [];
    existing.push({
        key: 'Set-Cookie',
        value: `app-version=${version}; Path=/; Max-Age=86400; Secure; HttpOnly`
    });
    response.headers['set-cookie'] = existing;
    response.headers['x-served-by'] = [{ key: 'X-Served-By', value: version }];

    return response;
};


### Problem with Lambda@Edge Only

Lambda@Edge runs on cache misses only. For returning users with a cookie:

User (cookie=V2) → CloudFront Cache → HIT → Returns V1 cached content ❌


The cache doesn't know about the version cookie, so it may serve wrong cached content. You need the cookie in the cache key, but
CloudFront cache policies can't dynamically route to different origins.

Solution: Include cookie in cache key.

### Cache Policies (per service)

bash
# Products: cached 1 hour, per version
PRODUCTS_CACHE=$(aws cloudfront create-cache-policy \
  --cache-policy-config '{
    "Name": "Products-Cache-BlueGreen",
    "DefaultTTL": 3600, "MaxTTL": 86400, "MinTTL": 0,
    "ParametersInCacheKeyAndForwardedToOrigin": {
      "EnableAcceptEncodingGzip": true,
      "EnableAcceptEncodingBrotli": true,
      "HeadersConfig": { "HeaderBehavior": "none" },
      "CookiesConfig": {
        "CookieBehavior": "whitelist",
        "Cookies": { "Quantity": 1, "Items": ["app-version"] }
      },
      "QueryStringsConfig": {
        "QueryStringBehavior": "whitelist",
        "QueryStrings": { "Quantity": 3, "Items": ["category","page","sort"] }
      }
    }
  }' --query 'CachePolicy.Id' --output text)

# Profile: cached per user + per version
PROFILE_CACHE=$(aws cloudfront create-cache-policy \
  --cache-policy-config '{
    "Name": "Profile-Cache-BlueGreen",
    "DefaultTTL": 300, "MaxTTL": 3600, "MinTTL": 0,
    "ParametersInCacheKeyAndForwardedToOrigin": {
      "EnableAcceptEncodingGzip": true,
      "EnableAcceptEncodingBrotli": true,
      "HeadersConfig": {
        "HeaderBehavior": "whitelist",
        "Headers": { "Quantity": 1, "Items": ["Authorization"] }
      },
      "CookiesConfig": {
        "CookieBehavior": "whitelist",
        "Cookies": { "Quantity": 1, "Items": ["app-version"] }
      },
      "QueryStringsConfig": { "QueryStringBehavior": "none" }
    }
  }' --query 'CachePolicy.Id' --output text)

# Payment: no cache (CachingDisabled managed policy)
PAYMENT_CACHE="4135ea2d-6df8-44a3-9df3-4b5a84be39ad"


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Option 2: Hybrid (CF Function + Lambda@Edge) - Recommended

CF Function assigns the variant on every request (including cache hits), Lambda@Edge switches origin on cache misses.

Every request:     CF Function → assigns variant → adds to cache key
Cache HIT:         Returns correct cached version (no Lambda needed)
Cache MISS:        Lambda@Edge → reads variant → switches origin


### CF Function - Viewer Request (runs every request)

javascript
// cf-func-version-request.js
function handler(event) {
    var request = event.request;
    var cookies = request.cookies;
    var version = 'V1';

    if (cookies['app-version'] && cookies['app-version'].value) {
        version = cookies['app-version'].value;
    } else {
        // 10% to V2
        var ip = event.viewer.ip;
        var hash = 0;
        for (var i = 0; i < ip.length; i++) {
            hash = ((hash << 5) - hash) + ip.charCodeAt(i);
            hash |= 0;
        }
        version = (Math.abs(hash) % 100) < 10 ? 'V2' : 'V1';
    }

    // Add to cache key (separate cache per version)
    request.headers['x-app-version'] = { value: version };

    return request;
}


### CF Function - Viewer Response (set cookie)

javascript
// cf-func-version-response.js
function handler(event) {
    var response = event.response;
    var request = event.request;
    var version = request.headers['x-app-version']
        ? request.headers['x-app-version'].value : 'V1';

    if (!request.cookies['app-version']) {
        response.cookies['app-version'] = {
            value: version,
            attributes: 'Path=/; Max-Age=86400; Secure; HttpOnly'
        };
    }

    response.headers['x-served-by'] = { value: version };
    return response;
}


### Lambda@Edge - Origin Request (switches origin on cache miss)

javascript
// lambda-origin-switch.js
'use strict';

const defined_origins = {
    'V1': 'alb-v1-xxxx.ap-southeast-1.elb.amazonaws.com',
    'V2': 'alb-v2-xxxx.ap-southeast-1.elb.amazonaws.com'
};

exports.handler = async (event) => {
    const request = event.Records[0].cf.request;

    // Read version from header (set by CF Function)
    const versionHeader = request.headers['x-app-version'];
    const version = versionHeader ? versionHeader[0].value : 'V1';

    // Switch origin
    const targetDomain = defined_origins[version];
    request.origin.custom.domainName = targetDomain;
    request.headers['host'] = [{ key: 'host', value: targetDomain }];

    return request;
};


### Deploy

bash
# CF Functions
aws cloudfront create-function \
  --name version-request \
  --function-config Comment="Version assignment",Runtime=cloudfront-js-2.0 \
  --function-code fileb://cf-func-version-request.js
ETAG=$(aws cloudfront describe-function --name version-request --query 'ETag' --output text)
aws cloudfront publish-function --name version-request --if-match $ETAG
CF_VER_REQ=$(aws cloudfront describe-function --name version-request \
  --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)

aws cloudfront create-function \
  --name version-response \
  --function-config Comment="Version set cookie",Runtime=cloudfront-js-2.0 \
  --function-code fileb://cf-func-version-response.js
ETAG=$(aws cloudfront describe-function --name version-response --query 'ETag' --output text)
aws cloudfront publish-function --name version-response --if-match $ETAG
CF_VER_RESP=$(aws cloudfront describe-function --name version-response \
  --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)

# Lambda@Edge (origin request only, no origin response needed)
zip lambda-origin-switch.zip lambda-origin-switch.js
LAMBDA_SWITCH_ARN=$(aws lambda create-function \
  --function-name origin-switch \
  --runtime nodejs18.x \
  --role $ROLE_ARN \
  --handler lambda-origin-switch.handler \
  --zip-file fileb://lambda-origin-switch.zip \
  --memory-size 128 --timeout 5 \
  --region us-east-1 \
  --query 'FunctionArn' --output text)

LAMBDA_SWITCH_VER=$(aws lambda publish-version \
  --function-name origin-switch --region us-east-1 \
  --query 'Version' --output text)


### Cache Policy (include version header in cache key)

bash
PRODUCTS_CACHE_BG=$(aws cloudfront create-cache-policy \
  --cache-policy-config '{
    "Name": "Products-BlueGreen",
    "DefaultTTL": 3600, "MaxTTL": 86400, "MinTTL": 0,
    "ParametersInCacheKeyAndForwardedToOrigin": {
      "EnableAcceptEncodingGzip": true,
      "EnableAcceptEncodingBrotli": true,
      "HeadersConfig": {
        "HeaderBehavior": "whitelist",
        "Headers": { "Quantity": 1, "Items": ["x-app-version"] }
      },
      "CookiesConfig": { "CookieBehavior": "none" },
      "QueryStringsConfig": {
        "QueryStringBehavior": "whitelist",
        "QueryStrings": { "Quantity": 3, "Items": ["category","page","sort"] }
      }
    }
  }' --query 'CachePolicy.Id' --output text)

PROFILE_CACHE_BG=$(aws cloudfront create-cache-policy \
  --cache-policy-config '{
    "Name": "Profile-BlueGreen",
    "DefaultTTL": 300, "MaxTTL": 3600, "MinTTL": 0,
    "ParametersInCacheKeyAndForwardedToOrigin": {
      "EnableAcceptEncodingGzip": true,
      "EnableAcceptEncodingBrotli": true,
      "HeadersConfig": {
        "HeaderBehavior": "whitelist",
        "Headers": { "Quantity": 2, "Items": ["Authorization", "x-app-version"] }
      },
      "CookiesConfig": { "CookieBehavior": "none" },
      "QueryStringsConfig": { "QueryStringBehavior": "none" }
    }
  }' --query 'CachePolicy.Id' --output text)


### Distribution Behavior Config

Each behavior gets CF Functions (viewer) + Lambda@Edge (origin):

json
{
  "PathPattern": "/api/products/*",
  "TargetOriginId": "ALB-V1",
  "CachePolicyId": "<PRODUCTS_CACHE_BG>",
  "FunctionAssociations": {
    "Quantity": 2,
    "Items": [
      { "FunctionARN": "<CF_VER_REQ>", "EventType": "viewer-request" },
      { "FunctionARN": "<CF_VER_RESP>", "EventType": "viewer-response" }
    ]
  },
  "LambdaFunctionAssociations": {
    "Quantity": 1,
    "Items": [
      { "LambdaFunctionARN": "<LAMBDA_SWITCH_ARN:VER>", "EventType": "origin-request", "IncludeBody": false }
    ]
  }
}


Same pattern for /api/profile/* and /api/payment/*.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Request Flow (Hybrid)

First visit (no cookie):
1. CF Function: hash IP → V2 (10%), add header x-app-version=V2
2. Cache lookup: /api/products/list|V2 → MISS
3. Lambda@Edge: read x-app-version=V2 → switch origin to ALB-V2
4. ALB-V2 → EC2-V2 → response
5. CloudFront caches as /api/products/list|V2
6. CF Function: set cookie app-version=V2

Return visit (has cookie):
1. CF Function: read cookie → V2, add header x-app-version=V2
2. Cache lookup: /api/products/list|V2 → HIT ✅
3. Lambda@Edge: NOT invoked (cache hit)
4. CF Function: cookie exists, skip set-cookie


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Comparison: Option 1 vs Option 2

| Aspect | Option 1 (Lambda Only) | Option 2 (Hybrid) |
|--------|----------------------|-------------------|
| Variant assignment | Lambda@Edge (cache miss) | CF Function (every request) |
| Origin switching | Lambda@Edge | Lambda@Edge |
| Cookie setting | Lambda@Edge | CF Function |
| Cache hit behavior | Needs cookie in cache key | Header in cache key (cleaner) |
| New user, cache hit | ❌ May serve wrong version | ✅ Always correct |
| Cost (1M req/day) | Lambda: ~$12/mo | CF Func: $3 + Lambda: ~$4 = $7/mo |
| Latency | 5-50ms on miss | <1ms always + 5-50ms on miss |
| Complexity | Simpler (2 Lambda functions) | More pieces (2 CF + 1 Lambda) |

Option 2 (Hybrid) is recommended because:
1. Cheaper - CF Function handles the frequent work, Lambda only for origin switching
2. Correct - Every request gets the right variant, even cache hits
3. Faster - CF Function adds <1ms, Lambda only on cache misses
4. Cleaner - Separation of concerns (assignment vs routing)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Rollout Strategy

bash
# Phase 1: 10% to V2
# In cf-func-version-request.js:
version = (Math.abs(hash) % 100) < 10 ? 'V2' : 'V1';

# Phase 2: 50% to V2 (after validation)
version = (Math.abs(hash) % 100) < 50 ? 'V2' : 'V1';

# Phase 3: 100% to V2
version = 'V2';

# Phase 4: Cleanup
# - Remove CF Functions and Lambda@Edge
# - Remove ALB-V1 origin
# - Update default origin to ALB-V2
# - Remove version from cache keys
# - Invalidate cache
aws cloudfront create-invalidation --distribution-id $DIST_ID --paths "/*"


### Instant Rollback

javascript
// Emergency: route 100% back to V1
// Update cf-func-version-request.js:
function handler(event) {
    var request = event.request;
    request.headers['x-app-version'] = { value: 'V1' };
    return request;
}
// Deploy in seconds, no Lambda redeployment needed


This is another advantage of the hybrid approach - rollback only requires updating the CF Function (seconds), not Lambda@Edge (
minutes for global replication).
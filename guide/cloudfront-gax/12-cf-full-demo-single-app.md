assume my application is built on ec2 with 3 services (products, payment, user profile). the application will run behind an ALB. i want to setup cloudfront distribution for the ALB with cache controls for 3 services (cached products with ttl in hour, user profile will be cached per user, payment will not be cached). 

Continue with above scenario, in the second scenarios, i have new version release that updated user profile in version 2 (UI/UX changed - eg: color of background), this will be implement via cloudfront function, user will randomly get variant A and B (version 2). 

in the third scenario, I have updated the new version for profile version 3 with 10% user will use this feature (the number of 10% and the color will get from dynamoDB) and implemented via cloudfront lambda@edge. 
please write the detail guide for 3 scenarios.

## Architecture

Users → CloudFront Distribution
          │
          ├── /api/products/*  → ALB → EC2 (cached, TTL=1 hour)
          ├── /api/profile/*   → ALB → EC2 (cached per user, via Authorization header)
          └── /api/payment/*   → ALB → EC2 (no cache, forward everything)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 1: Create Cache Policies

### Products Cache Policy (TTL = 1 hour)

bash
PRODUCTS_CACHE_POLICY=$(aws cloudfront create-cache-policy \
  --cache-policy-config '{
    "Name": "Products-Cache-1Hour",
    "Comment": "Cache products for 1 hour",
    "DefaultTTL": 3600,
    "MaxTTL": 86400,
    "MinTTL": 0,
    "ParametersInCacheKeyAndForwardedToOrigin": {
      "EnableAcceptEncodingGzip": true,
      "EnableAcceptEncodingBrotli": true,
      "HeadersConfig": { "HeaderBehavior": "none" },
      "CookiesConfig": { "CookieBehavior": "none" },
      "QueryStringsConfig": {
        "QueryStringBehavior": "whitelist",
        "QueryStrings": {
          "Quantity": 3,
          "Items": ["category", "page", "sort"]
        }
      }
    }
  }' \
  --query 'CachePolicy.Id' --output text)


### Profile Cache Policy (per user via Authorization header)

bash
PROFILE_CACHE_POLICY=$(aws cloudfront create-cache-policy \
  --cache-policy-config '{
    "Name": "Profile-Cache-PerUser",
    "Comment": "Cache per user using Authorization header",
    "DefaultTTL": 300,
    "MaxTTL": 3600,
    "MinTTL": 0,
    "ParametersInCacheKeyAndForwardedToOrigin": {
      "EnableAcceptEncodingGzip": true,
      "EnableAcceptEncodingBrotli": true,
      "HeadersConfig": {
        "HeaderBehavior": "whitelist",
        "Headers": {
          "Quantity": 1,
          "Items": ["Authorization"]
        }
      },
      "CookiesConfig": { "CookieBehavior": "none" },
      "QueryStringsConfig": { "QueryStringBehavior": "none" }
    }
  }' \
  --query 'CachePolicy.Id' --output text)


### Payment - No Cache (use managed CachingDisabled policy)

bash
# AWS Managed CachingDisabled policy
PAYMENT_CACHE_POLICY="4135ea2d-6df8-44a3-9df3-4b5a84be39ad"


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 2: Create Origin Request Policies

Origin request policies control what gets forwarded to ALB (independent of cache key).

### Products Origin Request Policy

bash
PRODUCTS_ORIGIN_POLICY=$(aws cloudfront create-origin-request-policy \
  --origin-request-policy-config '{
    "Name": "Products-Origin-Request",
    "Comment": "Forward minimal headers to ALB for products",
    "HeadersConfig": {
      "HeaderBehavior": "whitelist",
      "Headers": {
        "Quantity": 2,
        "Items": ["Accept", "Accept-Language"]
      }
    },
    "CookiesConfig": { "CookieBehavior": "none" },
    "QueryStringsConfig": { "QueryStringBehavior": "all" }
  }' \
  --query 'OriginRequestPolicy.Id' --output text)


### Profile Origin Request Policy

bash
PROFILE_ORIGIN_POLICY=$(aws cloudfront create-origin-request-policy \
  --origin-request-policy-config '{
    "Name": "Profile-Origin-Request",
    "Comment": "Forward auth headers to ALB for profile",
    "HeadersConfig": {
      "HeaderBehavior": "whitelist",
      "Headers": {
        "Quantity": 2,
        "Items": ["Authorization", "Accept"]
      }
    },
    "CookiesConfig": { "CookieBehavior": "none" },
    "QueryStringsConfig": { "QueryStringBehavior": "none" }
  }' \
  --query 'OriginRequestPolicy.Id' --output text)


### Payment Origin Request Policy

bash
# Use AWS Managed AllViewer policy - forwards everything
PAYMENT_ORIGIN_POLICY="216adef6-5c7f-47e4-b989-5492eafa07d3"


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 3: Create CloudFront Distribution

bash
cat > dist-config.json << EOF
{
  "CallerReference": "$(date +%s)",
  "Comment": "ALB with per-service cache policies",
  "Enabled": true,
  "PriceClass": "PriceClass_100",
  "Origins": {
    "Quantity": 1,
    "Items": [{
      "Id": "ALB-Origin",
      "DomainName": "${ALB_DNS}",
      "CustomOriginConfig": {
        "HTTPPort": 80,
        "HTTPSPort": 443,
        "OriginProtocolPolicy": "http-only",
        "OriginSslProtocols": { "Quantity": 1, "Items": ["TLSv1.2"] },
        "OriginReadTimeout": 30,
        "OriginKeepaliveTimeout": 5
      }
    }]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "ALB-Origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": { "Quantity": 7, "Items": ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"], "CachedMethods": { "Quantity": 2, "Items": ["GET","HEAD"] } },
    "Compress": true,
    "CachePolicyId": "${PAYMENT_CACHE_POLICY}",
    "OriginRequestPolicyId": "${PAYMENT_ORIGIN_POLICY}"
  },
  "CacheBehaviors": {
    "Quantity": 3,
    "Items": [
      {
        "PathPattern": "/api/products/*",
        "TargetOriginId": "ALB-Origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": { "Quantity": 2, "Items": ["GET","HEAD"], "CachedMethods": { "Quantity": 2, "Items": ["GET","HEAD"] } },
        "Compress": true,
        "CachePolicyId": "${PRODUCTS_CACHE_POLICY}",
        "OriginRequestPolicyId": "${PRODUCTS_ORIGIN_POLICY}"
      },
      {
        "PathPattern": "/api/profile/*",
        "TargetOriginId": "ALB-Origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": { "Quantity": 3, "Items": ["GET","HEAD","OPTIONS"], "CachedMethods": { "Quantity": 2, "Items": ["GET","HEAD"] } },
        "Compress": true,
        "CachePolicyId": "${PROFILE_CACHE_POLICY}",
        "OriginRequestPolicyId": "${PROFILE_ORIGIN_POLICY}"
      },
      {
        "PathPattern": "/api/payment/*",
        "TargetOriginId": "ALB-Origin",
        "ViewerProtocolPolicy": "https-only",
        "AllowedMethods": { "Quantity": 7, "Items": ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"], "CachedMethods": { "Quantity": 2, "Items": ["GET","HEAD"] } },
        "Compress": true,
        "CachePolicyId": "${PAYMENT_CACHE_POLICY}",
        "OriginRequestPolicyId": "${PAYMENT_ORIGIN_POLICY}"
      }
    ]
  }
}
EOF

DIST_ID=$(aws cloudfront create-distribution \
  --distribution-config file://dist-config.json \
  --query 'Distribution.Id' --output text)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 4: EC2 Application with Cache-Control Headers

The application must send correct Cache-Control headers so CloudFront respects the intended caching behavior.

javascript
// server.js
const http = require('http');
const url = require('url');

http.createServer((req, res) => {
    const path = url.parse(req.url, true).pathname;
    const query = url.parse(req.url, true).query;
    res.setHeader('Content-Type', 'application/json');

    // --- PRODUCTS: cached 1 hour ---
    if (path.startsWith('/api/products')) {
        res.setHeader('Cache-Control', 'public, max-age=3600, s-maxage=3600');

        if (path === '/api/products/list') {
            res.end(JSON.stringify({
                products: [
                    { id: 1, name: 'Widget A', price: 29.99 },
                    { id: 2, name: 'Widget B', price: 49.99 }
                ],
                category: query.category || 'all',
                page: query.page || 1,
                cached_until: new Date(Date.now() + 3600000).toISOString()
            }));
        } else {
            const id = path.split('/').pop();
            res.end(JSON.stringify({
                id, name: `Product ${id}`, price: 19.99,
                cached_until: new Date(Date.now() + 3600000).toISOString()
            }));
        }

    // --- PROFILE: cached per user, 5 min ---
    } else if (path.startsWith('/api/profile')) {
        const authHeader = req.headers['authorization'] || 'anonymous';
        // s-maxage for CloudFront, private prevents shared caches without auth
        res.setHeader('Cache-Control', 'private, max-age=300, s-maxage=300');
        res.setHeader('Vary', 'Authorization');

        res.end(JSON.stringify({
            user: authHeader.replace('Bearer ', '').substring(0, 8) + '...',
            name: 'Demo User',
            email: '<email>',
            cached_until: new Date(Date.now() + 300000).toISOString()
        }));

    // --- PAYMENT: never cached ---
    } else if (path.startsWith('/api/payment')) {
        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
        res.setHeader('Pragma', 'no-cache');
        res.setHeader('Expires', '0');

        if (req.method === 'POST') {
            let body = '';
            req.on('data', chunk => body += chunk);
            req.on('end', () => {
                res.end(JSON.stringify({
                    transactionId: 'txn-' + Date.now(),
                    status: 'processed',
                    timestamp: new Date().toISOString()
                }));
            });
            return;
        }
        res.end(JSON.stringify({
            status: 'payment-api-ready',
            timestamp: new Date().toISOString()
        }));

    // --- HEALTH CHECK ---
    } else if (path === '/api/health') {
        res.end(JSON.stringify({ status: 'ok' }));

    } else {
        res.writeHead(404);
        res.end(JSON.stringify({ error: 'Not found' }));
    }
}).listen(80);

Example 2:
// server.js
const http = require('http');
const url = require('url');

http.createServer((req, res) => {
    const path = url.parse(req.url, true).pathname;
    const query = url.parse(req.url, true).query;
    res.setHeader('Content-Type', 'application/json');

    // Products Service - cacheable
    if (path.startsWith('/api/products')) {
        res.setHeader('Cache-Control', 'public, max-age=3600'); // 1 hour
        res.writeHead(200);
        res.end(JSON.stringify({
            products: [
                { id: 1, name: 'Product A', price: 29.99 },
                { id: 2, name: 'Product B', price: 49.99 }
            ],
            category: query.category || 'all',
            page: query.page || 1,
            generatedAt: new Date().toISOString()
        }));
        return;
    }

    // Profile Service - cached per user
    if (path.startsWith('/api/profile')) {
        const variant = req.headers['x-ab-variant'] || 'default';
        res.setHeader('Cache-Control', 'private, max-age=300'); // 5 min per user
        res.writeHead(200);
        res.end(JSON.stringify({
            userId: req.headers['authorization'] || 'anonymous',
            name: 'Demo User',
            variant: variant,
            theme: variant === 'B' ? { background: '#1a1a2e' } :
                   variant === 'C' ? { background: '#dynamodb-color' } :
                   { background: '#ffffff' },
            generatedAt: new Date().toISOString()
        }));
        return;
    }

    // Payment Service - no cache
    if (path.startsWith('/api/payment')) {
        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
        res.writeHead(200);
        res.end(JSON.stringify({
            transactionId: 'txn-' + Date.now(),
            status: 'processed',
            timestamp: new Date().toISOString()
        }));
        return;
    }

    // Health check
    if (path === '/health') {
        res.writeHead(200);
        res.end(JSON.stringify({ status: 'ok' }));
        return;
    }

    res.writeHead(404);
    res.end(JSON.stringify({ error: 'Not found' }));
}).listen(80);


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cache Behavior Summary

| Service | Path | Cache Policy | TTL | Cache Key | Origin Request |
|---------|------|-------------|-----|-----------|----------------|
| Products | /api/products/* | Products-Cache-1Hour | 1 hour | URI + category, page, sort | Accept, Accept-Language, all query 
strings |
| Profile | /api/profile/* | Profile-Cache-PerUser | 5 min | URI + Authorization header | Authorization, Accept |
| Payment | /api/payment/* | CachingDisabled | 0 | N/A (no cache) | All headers, cookies, query strings |
| Default | /* | CachingDisabled | 0 | N/A | All (fallback) |

### How Each Cache Works

Products:
User A: GET /api/products/list?category=electronics&page=1
  → Cache Key: /api/products/list|electronics|1
  → Cache HIT for all users requesting same category+page
  → TTL: 1 hour

User B: GET /api/products/list?category=electronics&page=1
  → Cache HIT (same cache key, no user-specific data)


Profile:
User A (token-aaa): GET /api/profile/me
  → Cache Key: /api/profile/me|Bearer token-aaa
  → Cache HIT only for User A
  → TTL: 5 minutes

User B (token-bbb): GET /api/profile/me
  → Cache Key: /api/profile/me|Bearer token-bbb
  → Cache MISS (different Authorization header = different cache key)


Payment:
Any request: POST /api/payment/checkout
  → Always forwarded to origin
  → Never cached
  → All headers/cookies/body forwarded


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Testing

bash
CF_DOMAIN=$(aws cloudfront get-distribution --id $DIST_ID \
  --query 'Distribution.DomainName' --output text)

# Test Products (should cache)
curl -v "https://${CF_DOMAIN}/api/products/list?category=electronics&page=1"
# First request: X-Cache: Miss from cloudfront
# Second request: X-Cache: Hit from cloudfront

# Test Profile (cached per user)
curl -v -H "Authorization: Bearer user-token-aaa" "https://${CF_DOMAIN}/api/profile/me"
# Cached for this token only

curl -v -H "Authorization: Bearer user-token-bbb" "https://${CF_DOMAIN}/api/profile/me"
# Different cache entry

# Test Payment (never cached)
curl -v -X POST "https://${CF_DOMAIN}/api/payment/checkout" \
  -H "Content-Type: application/json" \
  -d '{"amount": 99.99}'
# Always: X-Cache: Miss from cloudfront


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cache Invalidation

bash
# Invalidate all products (after price update)
aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/api/products/*"

# Invalidate specific product
aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/api/products/123"

# Invalidate all profile caches
aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/api/profile/*"

# Cost: First 1,000 invalidation paths/month free, then $0.005 per path


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Estimate

Assuming 1M requests/day (30M/month):
- 60% products, 30% profile, 10% payment
- Products cache hit: 80%, Profile cache hit: 50%

| Component | Calculation | Monthly Cost |
|-----------|-------------|-------------|
| CloudFront Requests | 30M × $0.0075/10K | $22.50 |
| CloudFront Data | 50GB × $0.085/GB | $4.25 |
| Origin Requests | | |
| - Products (cache miss 20%) | 18M × 0.2 = 3.6M | Hits ALB |
| - Profile (cache miss 50%) | 9M × 0.5 = 4.5M | Hits ALB |
| - Payment (always) | 3M | Hits ALB |
| ALB | $16.43 + LCU | ~$25.00 |
| EC2 ASG (2× t3.small) | 2 × $15.18 | $30.36 |
| Total | | ~$82.11 |

Without CloudFront (all requests hit ALB):
- ALB would handle 30M requests → higher LCU cost ~$45
- EC2 would need more capacity → 3-4 instances ~$60
- Data transfer from EC2: 50GB × $0.09 = $4.50
- **Total without CF: ~$109.50**

CloudFront saves ~$27/month + provides global edge caching, DDoS protection, and lower latency.

### Verify Caching Behavior

bash
CF_DOMAIN="dxxxxxx.cloudfront.net"

# Products - should see same generatedAt on repeated calls (cached)
curl -s "https://${CF_DOMAIN}/api/products/?category=electronics" | jq .generatedAt
sleep 2
curl -s "https://${CF_DOMAIN}/api/products/?category=electronics" | jq .generatedAt
# Same timestamp = cache hit ✓

# Profile - different per Authorization header
curl -s -H "Authorization: user-123" "https://${CF_DOMAIN}/api/profile/" | jq .generatedAt
curl -s -H "Authorization: user-456" "https://${CF_DOMAIN}/api/profile/" | jq .generatedAt
# Different timestamps = per-user cache ✓

# Payment - always fresh
curl -s "https://${CF_DOMAIN}/api/payment/" | jq .transactionId
curl -s "https://${CF_DOMAIN}/api/payment/" | jq .transactionId
# Different transactionId = no cache ✓



## A/B Testing for Profile V2 via CloudFront Function

### Architecture

User → CloudFront
         │
         ├── /api/products/*  → ALB (cached 1 hour, unchanged)
         ├── /api/profile/*   → ALB (cached per user + per variant)
         │     ├── CF Function (Viewer Request): assign variant, add to cache key
         │     └── CF Function (Viewer Response): set variant cookie
         └── /api/payment/*   → ALB (no cache, unchanged)


### Key Challenge

Profile is already cached per user (Authorization header). Now we need to cache per user AND per variant:

Before: Cache Key = /api/profile/me | Authorization
After:  Cache Key = /api/profile/me | Authorization | Variant(A or B)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 1: CloudFront Functions

### Viewer Request - Assign Variant

javascript
// cf-func-profile-ab-request.js
function handler(event) {
    var request = event.request;
    var cookies = request.cookies;
    var variant = 'A';

    // Check existing cookie
    if (cookies['profile-variant'] && cookies['profile-variant'].value) {
        variant = cookies['profile-variant'].value;
    } else {
        // Deterministic random using viewer IP
        var ip = event.viewer.ip;
        var hash = 0;
        for (var i = 0; i < ip.length; i++) {
            hash = ((hash << 5) - hash) + ip.charCodeAt(i);
            hash |= 0;
        }
        variant = (Math.abs(hash) % 100) < 50 ? 'A' : 'B';
    }

    // Header for origin to read
    request.headers['x-profile-variant'] = { value: variant };
    // Include in cache key so A and B are cached separately
    request.headers['x-profile-variant-cache'] = { value: variant };

    return request;
}


### Viewer Response - Set Cookie

javascript
// cf-func-profile-ab-response.js
function handler(event) {
    var response = event.response;
    var request = event.request;
    var variant = request.headers['x-profile-variant']
        ? request.headers['x-profile-variant'].value : 'A';

    // Set cookie if not present
    if (!request.cookies['profile-variant']) {
        response.cookies['profile-variant'] = {
            value: variant,
            attributes: 'Path=/api/profile; Max-Age=86400; Secure; HttpOnly'
        };
    }

    // Debug header
    response.headers['x-profile-variant'] = { value: variant };

    return response;
}


### Deploy

bash
# Viewer Request
aws cloudfront create-function \
  --name profile-ab-request \
  --function-config Comment="Profile A/B variant assignment",Runtime=cloudfront-js-2.0 \
  --function-code fileb://cf-func-profile-ab-request.js

ETAG=$(aws cloudfront describe-function --name profile-ab-request --query 'ETag' --output text)
aws cloudfront publish-function --name profile-ab-request --if-match $ETAG

CF_PROFILE_REQ=$(aws cloudfront describe-function --name profile-ab-request \
  --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)

# Viewer Response
aws cloudfront create-function \
  --name profile-ab-response \
  --function-config Comment="Profile A/B set cookie",Runtime=cloudfront-js-2.0 \
  --function-code fileb://cf-func-profile-ab-response.js

ETAG=$(aws cloudfront describe-function --name profile-ab-response --query 'ETag' --output text)
aws cloudfront publish-function --name profile-ab-response --if-match $ETAG

CF_PROFILE_RESP=$(aws cloudfront describe-function --name profile-ab-response \
  --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 2: Update Profile Cache Policy

Add x-profile-variant-cache header to cache key so each variant is cached separately per user.

bash
PROFILE_CACHE_POLICY_V2=$(aws cloudfront create-cache-policy \
  --cache-policy-config '{
    "Name": "Profile-Cache-PerUser-AB",
    "Comment": "Cache per user + per A/B variant",
    "DefaultTTL": 300,
    "MaxTTL": 3600,
    "MinTTL": 0,
    "ParametersInCacheKeyAndForwardedToOrigin": {
      "EnableAcceptEncodingGzip": true,
      "EnableAcceptEncodingBrotli": true,
      "HeadersConfig": {
        "HeaderBehavior": "whitelist",
        "Headers": {
          "Quantity": 2,
          "Items": ["Authorization", "x-profile-variant-cache"]
        }
      },
      "CookiesConfig": { "CookieBehavior": "none" },
      "QueryStringsConfig": { "QueryStringBehavior": "none" }
    }
  }' \
  --query 'CachePolicy.Id' --output text)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 3: Update Distribution - Profile Behavior

bash
# Get current config
aws cloudfront get-distribution-config --id $DIST_ID > current-config.json
ETAG=$(jq -r '.ETag' current-config.json)

# Extract and modify DistributionConfig
jq '.DistributionConfig' current-config.json > update-config.json


Update the /api/profile/* cache behavior in update-config.json:

bash
# Update profile behavior with new cache policy + CF functions
jq --arg cachePolicy "$PROFILE_CACHE_POLICY_V2" \
   --arg cfReq "$CF_PROFILE_REQ" \
   --arg cfResp "$CF_PROFILE_RESP" \
   '(.CacheBehaviors.Items[] | select(.PathPattern == "/api/profile/*")) |=
    . + {
      "CachePolicyId": $cachePolicy,
      "FunctionAssociations": {
        "Quantity": 2,
        "Items": [
          { "FunctionARN": $cfReq, "EventType": "viewer-request" },
          { "FunctionARN": $cfResp, "EventType": "viewer-response" }
        ]
      }
    }' update-config.json > final-config.json

aws cloudfront update-distribution \
  --id $DIST_ID \
  --if-match $ETAG \
  --distribution-config file://final-config.json


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 4: Update EC2 Application - Profile Endpoint

Only the profile handler changes. It reads x-profile-variant header and returns different UI config.

javascript
// Update the profile section in server.js
    } else if (path.startsWith('/api/profile')) {
        const authHeader = req.headers['authorization'] || 'anonymous';
        const variant = req.headers['x-profile-variant'] || 'A';

        res.setHeader('Cache-Control', 'private, max-age=300, s-maxage=300');
        res.setHeader('Vary', 'Authorization');

        // V1 (Variant A) vs V2 (Variant B) UI config
        const uiConfig = variant === 'B' ? {
            version: 'v2',
            backgroundColor: '#1a1a2e',
            textColor: '#e0e0e0',
            accentColor: '#e94560',
            layout: 'card-grid',
            showAvatar: true,
            sidebarPosition: 'left'
        } : {
            version: 'v1',
            backgroundColor: '#ffffff',
            textColor: '#333333',
            accentColor: '#ff9900',
            layout: 'list',
            showAvatar: false,
            sidebarPosition: 'right'
        };

        res.end(JSON.stringify({
            user: authHeader.replace('Bearer ', '').substring(0, 8) + '...',
            name: 'Demo User',
            email: '<email>',
            variant: variant,
            ui: uiConfig,
            cached_until: new Date(Date.now() + 300000).toISOString()
        }));


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## How It Works End-to-End

### New User (no cookie)

1. User requests GET /api/profile/me
   Headers: Authorization: Bearer token-aaa

2. CloudFront Function (Viewer Request):
   - No profile-variant cookie found
   - Hash viewer IP → assigns variant B
   - Adds: x-profile-variant: B
   - Adds: x-profile-variant-cache: B

3. CloudFront Cache Lookup:
   - Cache Key: /api/profile/me | Bearer token-aaa | B
   - Cache MISS

4. ALB → EC2:
   - Reads x-profile-variant: B
   - Returns V2 UI config (dark background, card-grid layout)

5. CloudFront Function (Viewer Response):
   - Sets cookie: profile-variant=B; Path=/api/profile; Max-Age=86400
   - Adds header: x-profile-variant: B

6. User sees V2 profile UI


### Returning User (has cookie)

1. User requests GET /api/profile/me
   Headers: Authorization: Bearer token-aaa
   Cookie: profile-variant=B

2. CloudFront Function (Viewer Request):
   - Reads cookie → variant B
   - Adds: x-profile-variant: B
   - Adds: x-profile-variant-cache: B

3. CloudFront Cache Lookup:
   - Cache Key: /api/profile/me | Bearer token-aaa | B
   - Cache HIT (cached from previous request)

4. User gets cached V2 response instantly
   (EC2 not hit)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cache Key Matrix

| User | Variant | Cache Key | Cached Separately |
|------|---------|-----------|-------------------|
| token-aaa | A | /api/profile/me \| token-aaa \| A | ✅ |
| token-aaa | B | /api/profile/me \| token-aaa \| B | ✅ |
| token-bbb | A | /api/profile/me \| token-bbb \| A | ✅ |
| token-bbb | B | /api/profile/me \| token-bbb \| B | ✅ |

Each user × variant combination has its own cache entry.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Testing

bash
CF_DOMAIN=$(aws cloudfront get-distribution --id $DIST_ID \
  --query 'Distribution.DomainName' --output text)

# Test without cookie (random assignment)
curl -v -H "Authorization: Bearer user-aaa" \
  "https://${CF_DOMAIN}/api/profile/me"
# Check: x-profile-variant header and set-cookie in response

# Test with Variant A cookie
curl -v -H "Authorization: Bearer user-aaa" \
  -H "Cookie: profile-variant=A" \
  "https://${CF_DOMAIN}/api/profile/me"
# Expect: ui.version = "v1", backgroundColor = "#ffffff"

# Test with Variant B cookie
curl -v -H "Authorization: Bearer user-aaa" \
  -H "Cookie: profile-variant=B" \
  "https://${CF_DOMAIN}/api/profile/me"
# Expect: ui.version = "v2", backgroundColor = "#1a1a2e"

# Verify separate caching
curl -H "Authorization: Bearer user-aaa" -H "Cookie: profile-variant=A" \
  "https://${CF_DOMAIN}/api/profile/me"  # Miss
curl -H "Authorization: Bearer user-aaa" -H "Cookie: profile-variant=A" \
  "https://${CF_DOMAIN}/api/profile/me"  # Hit (same user + variant)
curl -H "Authorization: Bearer user-aaa" -H "Cookie: profile-variant=B" \
  "https://${CF_DOMAIN}/api/profile/me"  # Miss (different variant)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cache Impact

### Before A/B (per user only)
Unique cache entries = Number of active users
1,000 users = 1,000 cache entries


### After A/B (per user × variant)
Unique cache entries = Number of active users × 2
1,000 users = 2,000 cache entries
Cache hit ratio drops slightly (split cache)


### Cost Impact (1M profile requests/day)

| Metric | Before A/B | After A/B | Change |
|--------|-----------|-----------|--------|
| Cache entries | 10K | 20K | 2× |
| Cache hit ratio | 50% | ~35% | -15% |
| Origin requests/day | 500K | 650K | +30% |
| CF Function cost | $0 | 30M × $0.10/M = $3.00/mo | +$3.00 |
| Extra ALB load | - | +150K req/day | Minimal |

Total additional cost: ~$3-5/month - very cost effective for A/B testing.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Rollout Strategy

### Phase 1: 10% to Variant B
javascript
// Change in cf-func-profile-ab-request.js
variant = (Math.abs(hash) % 100) < 10 ? 'B' : 'A';  // 10% get B


### Phase 2: 50/50
javascript
variant = (Math.abs(hash) % 100) < 50 ? 'B' : 'A';  // 50% get B


### Phase 3: Full rollout to V2
javascript
// Remove A/B function, make V2 the default
// Or set 100% to B
variant = 'B';


### Phase 4: Cleanup
- Remove CloudFront Functions from profile behavior
- Revert cache policy to original (remove variant from cache key)
- Remove variant logic from EC2 application
- Invalidate profile cache: aws cloudfront create-invalidation --distribution-id $DIST_ID --paths "/api/profile/*"



## Profile A/B Testing - 3 Scenarios Complete Guide

### Architecture Overview

Scenario 1: No A/B (baseline)
User → CloudFront → Cache (per user) → ALB → EC2

Scenario 2: A/B via CloudFront Function (50/50, hardcoded config)
User → CF Function → Cache (per user + variant) → ALB → EC2

Scenario 3: A/B via Lambda@Edge (10%, config from DynamoDB)
User → CloudFront → Cache miss → Lambda@Edge → DynamoDB → ALB → EC2


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Scenario 1: No A/B Testing (Baseline V1)

### Cache Policy

bash
PROFILE_CACHE_V1=$(aws cloudfront create-cache-policy \
  --cache-policy-config '{
    "Name": "Profile-Cache-V1",
    "Comment": "Cache per user only",
    "DefaultTTL": 300,
    "MaxTTL": 3600,
    "MinTTL": 0,
    "ParametersInCacheKeyAndForwardedToOrigin": {
      "EnableAcceptEncodingGzip": true,
      "EnableAcceptEncodingBrotli": true,
      "HeadersConfig": {
        "HeaderBehavior": "whitelist",
        "Headers": { "Quantity": 1, "Items": ["Authorization"] }
      },
      "CookiesConfig": { "CookieBehavior": "none" },
      "QueryStringsConfig": { "QueryStringBehavior": "none" }
    }
  }' \
  --query 'CachePolicy.Id' --output text)


### EC2 Application

javascript
// profile-v1.js handler
function handleProfile(req, res) {
    const authHeader = req.headers['authorization'] || 'anonymous';
    res.setHeader('Cache-Control', 'private, max-age=300, s-maxage=300');

    res.end(JSON.stringify({
        user: authHeader.replace('Bearer ', '').substring(0, 8) + '...',
        name: 'Demo User',
        email: '<email>',
        ui: {
            version: 'v1',
            backgroundColor: '#ffffff',
            textColor: '#333333',
            accentColor: '#ff9900',
            layout: 'list'
        }
    }));
}


### Cache Behavior

Cache Key: /api/profile/me | Authorization
Cache entries per user: 1
No functions attached


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Scenario 2: A/B via CloudFront Function (V1 vs V2, 50/50)

### CloudFront Function - Viewer Request

javascript
// cf-func-profile-ab-request.js
function handler(event) {
    var request = event.request;
    var cookies = request.cookies;
    var variant = 'A';

    if (cookies['profile-variant'] && cookies['profile-variant'].value) {
        variant = cookies['profile-variant'].value;
    } else {
        var ip = event.viewer.ip;
        var hash = 0;
        for (var i = 0; i < ip.length; i++) {
            hash = ((hash << 5) - hash) + ip.charCodeAt(i);
            hash |= 0;
        }
        variant = (Math.abs(hash) % 100) < 50 ? 'A' : 'B';
    }

    request.headers['x-profile-variant'] = { value: variant };
    request.headers['x-profile-variant-cache'] = { value: variant };
    return request;
}


### CloudFront Function - Viewer Response

javascript
// cf-func-profile-ab-response.js
function handler(event) {
    var response = event.response;
    var request = event.request;
    var variant = request.headers['x-profile-variant']
        ? request.headers['x-profile-variant'].value : 'A';

    if (!request.cookies['profile-variant']) {
        response.cookies['profile-variant'] = {
            value: variant,
            attributes: 'Path=/api/profile; Max-Age=86400; Secure; HttpOnly'
        };
    }

    response.headers['x-profile-variant'] = { value: variant };
    return response;
}


### Updated Cache Policy

bash
PROFILE_CACHE_V2=$(aws cloudfront create-cache-policy \
  --cache-policy-config '{
    "Name": "Profile-Cache-V2-AB",
    "Comment": "Cache per user + variant",
    "DefaultTTL": 300,
    "MaxTTL": 3600,
    "MinTTL": 0,
    "ParametersInCacheKeyAndForwardedToOrigin": {
      "EnableAcceptEncodingGzip": true,
      "EnableAcceptEncodingBrotli": true,
      "HeadersConfig": {
        "HeaderBehavior": "whitelist",
        "Headers": { "Quantity": 2, "Items": ["Authorization", "x-profile-variant-cache"] }
      },
      "CookiesConfig": { "CookieBehavior": "none" },
      "QueryStringsConfig": { "QueryStringBehavior": "none" }
    }
  }' \
  --query 'CachePolicy.Id' --output text)


### Deploy Functions

bash
aws cloudfront create-function \
  --name profile-ab-request \
  --function-config Comment="Profile A/B assignment",Runtime=cloudfront-js-2.0 \
  --function-code fileb://cf-func-profile-ab-request.js
ETAG=$(aws cloudfront describe-function --name profile-ab-request --query 'ETag' --output text)
aws cloudfront publish-function --name profile-ab-request --if-match $ETAG
CF_AB_REQ=$(aws cloudfront describe-function --name profile-ab-request \
  --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)

aws cloudfront create-function \
  --name profile-ab-response \
  --function-config Comment="Profile A/B set cookie",Runtime=cloudfront-js-2.0 \
  --function-code fileb://cf-func-profile-ab-response.js
ETAG=$(aws cloudfront describe-function --name profile-ab-response --query 'ETag' --output text)
aws cloudfront publish-function --name profile-ab-response --if-match $ETAG
CF_AB_RESP=$(aws cloudfront describe-function --name profile-ab-response \
  --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)


### EC2 Application

javascript
// profile-v2.js handler
function handleProfile(req, res) {
    const authHeader = req.headers['authorization'] || 'anonymous';
    const variant = req.headers['x-profile-variant'] || 'A';
    res.setHeader('Cache-Control', 'private, max-age=300, s-maxage=300');

    const uiConfig = variant === 'B' ? {
        version: 'v2',
        backgroundColor: '#1a1a2e',
        textColor: '#e0e0e0',
        accentColor: '#e94560',
        layout: 'card-grid'
    } : {
        version: 'v1',
        backgroundColor: '#ffffff',
        textColor: '#333333',
        accentColor: '#ff9900',
        layout: 'list'
    };

    res.end(JSON.stringify({
        user: authHeader.replace('Bearer ', '').substring(0, 8) + '...',
        name: 'Demo User',
        email: '<email>',
        variant,
        ui: uiConfig
    }));
}


### Cache Behavior

Cache Key: /api/profile/me | Authorization | Variant(A/B)
Cache entries per user: 2
Functions: CF Function on Viewer Request + Viewer Response
Limitations: 50/50 hardcoded, UI config hardcoded in EC2


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Scenario 3: A/B via Lambda@Edge (V1 vs V2 vs V3, config from DynamoDB)

### DynamoDB Setup

bash
aws dynamodb create-table \
  --table-name ab-test-config \
  --attribute-definitions AttributeName=testId,AttributeType=S \
  --key-schema AttributeName=testId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1

# Insert config
aws dynamodb put-item \
  --table-name ab-test-config \
  --item '{
    "testId": {"S": "profile-ui"},
    "enabled": {"BOOL": true},
    "variants": {"L": [
      {"M": {
        "name": {"S": "A"},
        "weight": {"N": "45"},
        "ui": {"M": {
          "version": {"S": "v1"},
          "backgroundColor": {"S": "#ffffff"},
          "textColor": {"S": "#333333"},
          "accentColor": {"S": "#ff9900"},
          "layout": {"S": "list"}
        }}
      }},
      {"M": {
        "name": {"S": "B"},
        "weight": {"N": "45"},
        "ui": {"M": {
          "version": {"S": "v2"},
          "backgroundColor": {"S": "#1a1a2e"},
          "textColor": {"S": "#e0e0e0"},
          "accentColor": {"S": "#e94560"},
          "layout": {"S": "card-grid"}
        }}
      }},
      {"M": {
        "name": {"S": "C"},
        "weight": {"N": "10"},
        "ui": {"M": {
          "version": {"S": "v3"},
          "backgroundColor": {"S": "#0d1117"},
          "textColor": {"S": "#c9d1d9"},
          "accentColor": {"S": "#58a6ff"},
          "layout": {"S": "dashboard"}
        }}
      }}
    ]},
    "updatedAt": {"S": "2026-02-11T14:00:00Z"}
  }' \
  --region us-east-1


### IAM Role for Lambda@Edge

bash
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
  --role-name lambda-edge-ab-dynamo-role \
  --assume-role-policy-document file://lambda-trust.json \
  --query 'Role.Arn' --output text)

aws iam attach-role-policy \
  --role-name lambda-edge-ab-dynamo-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# DynamoDB read access
cat > dynamo-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["dynamodb:GetItem"],
    "Resource": "arn:aws:dynamodb:us-east-1:*:table/ab-test-config"
  }]
}
EOF

aws iam put-role-policy \
  --role-name lambda-edge-ab-dynamo-role \
  --policy-name dynamo-read \
  --policy-document file://dynamo-policy.json

sleep 10


### Lambda@Edge - Origin Request (with DynamoDB + caching)

javascript
// lambda-profile-ab-origin-request.js
'use strict';
const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient({ region: 'us-east-1' });

// In-memory cache (persists across warm invocations)
let configCache = null;
let cacheExpiry = 0;
const CACHE_TTL_MS = 60000; // 1 minute

async function getConfig() {
    const now = Date.now();
    if (configCache && now < cacheExpiry) return configCache;

    const result = await dynamodb.get({
        TableName: 'ab-test-config',
        Key: { testId: 'profile-ui' }
    }).promise();

    configCache = result.Item;
    cacheExpiry = now + CACHE_TTL_MS;
    return configCache;
}

function selectVariant(config, hash) {
    const variants = config.variants;
    let cumulative = 0;
    const roll = Math.abs(hash) % 100;

    for (const v of variants) {
        cumulative += v.weight;
        if (roll < cumulative) return v;
    }
    return variants[0]; // fallback
}

exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    const cookies = request.headers.cookie || [];

    // Check existing cookie
    let variantName = null;
    for (const c of cookies) {
        const match = c.value.match(/profile-variant=([A-Z])/);
        if (match) { variantName = match[1]; break; }
    }

    try {
        const config = await getConfig();

        if (!config || !config.enabled) {
            // A/B disabled, pass through as variant A
            request.headers['x-profile-variant'] = [{ key: 'X-Profile-Variant', value: 'A' }];
            return request;
        }

        let selectedVariant;

        if (variantName) {
            // Find matching variant from config
            selectedVariant = config.variants.find(v => v.name === variantName);
            if (!selectedVariant) selectedVariant = config.variants[0];
        } else {
            // Assign randomly based on weights
            const ip = request.clientIp || '0.0.0.0';
            let hash = 0;
            for (let i = 0; i < ip.length; i++) {
                hash = ((hash << 5) - hash) + ip.charCodeAt(i);
                hash |= 0;
            }
            selectedVariant = selectVariant(config, hash);
        }

        // Pass variant name and full UI config to origin
        request.headers['x-profile-variant'] = [
            { key: 'X-Profile-Variant', value: selectedVariant.name }
        ];
        request.headers['x-profile-ui-config'] = [
            { key: 'X-Profile-UI-Config', value: JSON.stringify(selectedVariant.ui) }
        ];

    } catch (err) {
        console.error('DynamoDB error:', err);
        // Fallback to variant A on error
        request.headers['x-profile-variant'] = [{ key: 'X-Profile-Variant', value: 'A' }];
    }

    return request;
};


### Lambda@Edge - Origin Response (set cookie)

javascript
// lambda-profile-ab-origin-response.js
'use strict';

exports.handler = async (event) => {
    const response = event.Records[0].cf.response;
    const request = event.Records[0].cf.request;

    const variantHeader = request.headers['x-profile-variant'];
    const variant = variantHeader ? variantHeader[0].value : 'A';

    // Set cookie
    const existingCookies = response.headers['set-cookie'] || [];
    existingCookies.push({
        key: 'Set-Cookie',
        value: `profile-variant=${variant}; Path=/api/profile; Max-Age=86400; Secure; HttpOnly`
    });
    response.headers['set-cookie'] = existingCookies;

    // Debug headers
    response.headers['x-profile-variant'] = [{ key: 'X-Profile-Variant', value: variant }];

    return response;
};


### Deploy Lambda@Edge

bash
# Origin Request
zip lambda-profile-ab-origin-request.zip lambda-profile-ab-origin-request.js
LAMBDA_OR_ARN=$(aws lambda create-function \
  --function-name profile-ab-origin-request \
  --runtime nodejs18.x \
  --role $ROLE_ARN \
  --handler lambda-profile-ab-origin-request.handler \
  --zip-file fileb://lambda-profile-ab-origin-request.zip \
  --memory-size 128 --timeout 5 \
  --region us-east-1 \
  --query 'FunctionArn' --output text)

LAMBDA_OR_VER=$(aws lambda publish-version \
  --function-name profile-ab-origin-request --region us-east-1 \
  --query 'Version' --output text)

# Origin Response
zip lambda-profile-ab-origin-response.zip lambda-profile-ab-origin-response.js
LAMBDA_ORESP_ARN=$(aws lambda create-function \
  --function-name profile-ab-origin-response \
  --runtime nodejs18.x \
  --role $ROLE_ARN \
  --handler lambda-profile-ab-origin-response.handler \
  --zip-file fileb://lambda-profile-ab-origin-response.zip \
  --memory-size 128 --timeout 5 \
  --region us-east-1 \
  --query 'FunctionArn' --output text)

LAMBDA_ORESP_VER=$(aws lambda publish-version \
  --function-name profile-ab-origin-response --region us-east-1 \
  --query 'Version' --output text)


### Updated Cache Policy for Scenario 3

bash
PROFILE_CACHE_V3=$(aws cloudfront create-cache-policy \
  --cache-policy-config '{
    "Name": "Profile-Cache-V3-AB-Lambda",
    "Comment": "Cache per user, variant added at origin level",
    "DefaultTTL": 300,
    "MaxTTL": 3600,
    "MinTTL": 0,
    "ParametersInCacheKeyAndForwardedToOrigin": {
      "EnableAcceptEncodingGzip": true,
      "EnableAcceptEncodingBrotli": true,
      "HeadersConfig": {
        "HeaderBehavior": "whitelist",
        "Headers": { "Quantity": 1, "Items": ["Authorization"] }
      },
      "CookiesConfig": {
        "CookieBehavior": "whitelist",
        "Cookies": { "Quantity": 1, "Items": ["profile-variant"] }
      },
      "QueryStringsConfig": { "QueryStringBehavior": "none" }
    }
  }' \
  --query 'CachePolicy.Id' --output text)


Why cookie in cache key? Lambda@Edge runs on origin request (cache miss only). Including the cookie in the cache key ensures 
returning users with a cookie get a cache hit for their variant without triggering Lambda@Edge again.

### Update Distribution - Profile Behavior for Scenario 3

bash
aws cloudfront get-distribution-config --id $DIST_ID > current-config.json
ETAG=$(jq -r '.ETag' current-config.json)
jq '.DistributionConfig' current-config.json > update-config.json

# Update profile behavior: remove CF Functions, add Lambda@Edge
jq --arg cachePolicy "$PROFILE_CACHE_V3" \
   --arg lambdaOr "${LAMBDA_OR_ARN}:${LAMBDA_OR_VER}" \
   --arg lambdaOresp "${LAMBDA_ORESP_ARN}:${LAMBDA_ORESP_VER}" \
   '(.CacheBehaviors.Items[] | select(.PathPattern == "/api/profile/*")) |=
    . + {
      "CachePolicyId": $cachePolicy,
      "FunctionAssociations": { "Quantity": 0 },
      "LambdaFunctionAssociations": {
        "Quantity": 2,
        "Items": [
          { "LambdaFunctionARN": $lambdaOr, "EventType": "origin-request", "IncludeBody": false },
          { "LambdaFunctionARN": $lambdaOresp, "EventType": "origin-response", "IncludeBody": false }
        ]
      }
    }' update-config.json > final-config.json

aws cloudfront update-distribution \
  --id $DIST_ID \
  --if-match $ETAG \
  --distribution-config file://final-config.json


### EC2 Application - Reads UI Config from Header

javascript
// profile-v3.js handler
function handleProfile(req, res) {
    const authHeader = req.headers['authorization'] || 'anonymous';
    const variant = req.headers['x-profile-variant'] || 'A';
    res.setHeader('Cache-Control', 'private, max-age=300, s-maxage=300');

    // UI config passed from Lambda@Edge (sourced from DynamoDB)
    let uiConfig;
    try {
        uiConfig = JSON.parse(req.headers['x-profile-ui-config']);
    } catch (e) {
        // Fallback if header missing
        uiConfig = {
            version: 'v1',
            backgroundColor: '#ffffff',
            textColor: '#333333',
            accentColor: '#ff9900',
            layout: 'list'
        };
    }

    res.end(JSON.stringify({
        user: authHeader.replace('Bearer ', '').substring(0, 8) + '...',
        name: 'Demo User',
        email: '<email>',
        variant,
        ui: uiConfig
    }));
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete EC2 Server (All 3 Scenarios Combined)

javascript
// server.js - supports all scenarios based on headers present
const http = require('http');
const url = require('url');

http.createServer((req, res) => {
    const path = url.parse(req.url, true).pathname;
    const query = url.parse(req.url, true).query;
    res.setHeader('Content-Type', 'application/json');

    if (path.startsWith('/api/products')) {
        res.setHeader('Cache-Control', 'public, max-age=3600, s-maxage=3600');
        res.end(JSON.stringify({
            products: [
                { id: 1, name: 'Widget A', price: 29.99 },
                { id: 2, name: 'Widget B', price: 49.99 }
            ],
            category: query.category || 'all',
            page: query.page || 1
        }));

    } else if (path.startsWith('/api/profile')) {
        const authHeader = req.headers['authorization'] || 'anonymous';
        const variant = req.headers['x-profile-variant'] || 'none';
        res.setHeader('Cache-Control', 'private, max-age=300, s-maxage=300');

        // Scenario 3: UI config from Lambda@Edge (DynamoDB)
        let uiConfig;
        if (req.headers['x-profile-ui-config']) {
            try { uiConfig = JSON.parse(req.headers['x-profile-ui-config']); }
            catch (e) { uiConfig = null; }
        }

        // Scenario 2: Hardcoded variant config
        if (!uiConfig && variant === 'B') {
            uiConfig = { version: 'v2', backgroundColor: '#1a1a2e', textColor: '#e0e0e0', accentColor: '#e94560', layout: 'card-grid' };
        }

        // Scenario 1: Default
        if (!uiConfig) {
            uiConfig = { version: 'v1', backgroundColor: '#ffffff', textColor: '#333333', accentColor: '#ff9900', layout: 'list' };
        }

        res.end(JSON.stringify({
            user: authHeader.replace('Bearer ', '').substring(0, 8) + '...',
            name: 'Demo User',
            email: '<email>',
            variant,
            ui: uiConfig
        }));

    } else if (path.startsWith('/api/payment')) {
        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
        if (req.method === 'POST') {
            let body = '';
            req.on('data', chunk => body += chunk);
            req.on('end', () => {
                res.end(JSON.stringify({ transactionId: 'txn-' + Date.now(), status: 'processed' }));
            });
            return;
        }
        res.end(JSON.stringify({ status: 'payment-api-ready' }));

    } else if (path === '/api/health') {
        res.end(JSON.stringify({ status: 'ok' }));
    } else {
        res.writeHead(404);
        res.end(JSON.stringify({ error: 'Not found' }));
    }
}).listen(80);


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## 3-Scenario Comparison

### Request Flow

Scenario 1 (No A/B):
User → CloudFront → Cache(user) → ALB → EC2 (hardcoded V1)

Scenario 2 (CF Function):
User → CF Function(assign variant) → Cache(user+variant) → ALB → EC2 (reads header)
     ← CF Function(set cookie) ←

Scenario 3 (Lambda@Edge):
User → CloudFront → Cache(user+cookie) HIT → return cached
                                         MISS → Lambda@Edge(DynamoDB) → ALB → EC2
     ← Lambda@Edge(set cookie) ←


### Feature Comparison

| Feature | Scenario 1 | Scenario 2 (CF Func) | Scenario 3 (Lambda@Edge) |
|---------|-----------|---------------------|-------------------------|
| Variants | 1 (V1 only) | 2 (A/B hardcoded) | 3+ (from DynamoDB) |
| Weight control | N/A | Hardcoded in JS | Dynamic from DynamoDB |
| UI config source | Hardcoded in EC2 | Hardcoded in EC2 | DynamoDB → Lambda → EC2 |
| Change weights | N/A | Redeploy CF Function | Update DynamoDB row |
| Change colors | Redeploy EC2 | Redeploy EC2 | Update DynamoDB row |
| Execution point | None | Every request | Cache misses only |
| Latency added | 0ms | <1ms | 5-50ms (on miss) |
| Network calls | None | Not possible | DynamoDB (cached 60s) |
| Deploy time | EC2 deploy | Seconds | Minutes |

### Cache Behavior

| Aspect | Scenario 1 | Scenario 2 | Scenario 3 |
|--------|-----------|-----------|-----------|
| Cache key | URI + Auth | URI + Auth + variant header | URI + Auth + variant cookie |
| Entries per user | 1 | 2 | Up to 3 |
| Function runs on | N/A | Every request | Cache miss only |
| Cache hit ratio | ~50% | ~35% | ~40% |

### Cost (1M profile requests/day, 30 days)

| Cost Item | Scenario 1 | Scenario 2 | Scenario 3 |
|-----------|-----------|-----------|-----------|
| CF Functions | $0 | 30M × $0.10/M = $3.00 | $0 |
| Lambda@Edge | $0 | $0 | ~18M misses × $0.60/M = $10.80 |
| Lambda duration | $0 | $0 | 18M × 10ms × 128MB = $1.15 |
| DynamoDB reads | $0 | $0 | ~$0.05 (cached, minimal) |
| Extra origin load | Baseline | +30% | +20% |
| Total A/B cost | $0 | $3.00/mo | $12.00/mo |

### When to Use Each

| Scenario | Use When |
|----------|----------|
| 1 - No A/B | Stable feature, no testing needed |
| 2 - CF Function | Simple A/B, fixed variants, hardcoded config, cost-sensitive |
| 3 - Lambda@Edge | Dynamic config, 3+ variants, frequent weight changes, UI config from DB |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Testing All 3 Scenarios

bash
CF_DOMAIN=$(aws cloudfront get-distribution --id $DIST_ID \
  --query 'Distribution.DomainName' --output text)

# Scenario 1: No A/B
curl -s -H "Authorization: Bearer user-aaa" \
  "https://${CF_DOMAIN}/api/profile/me" | jq .
# Expect: variant: "none", ui.version: "v1"

# Scenario 2: CF Function A/B (when CF Functions attached)
curl -s -H "Authorization: Bearer user-aaa" \
  -H "Cookie: profile-variant=B" \
  "https://${CF_DOMAIN}/api/profile/me" | jq .
# Expect: variant: "B", ui.version: "v2"

# Scenario 3: Lambda@Edge (when Lambda attached)
# No cookie - Lambda assigns based on weight (45/45/10)
curl -v -H "Authorization: Bearer user-aaa" \
  "https://${CF_DOMAIN}/api/profile/me"
# Check set-cookie header for assigned variant

# Force variant C (V3 - 10% group)
curl -s -H "Authorization: Bearer user-aaa" \
  -H "Cookie: profile-variant=C" \
  "https://${CF_DOMAIN}/api/profile/me" | jq .
# Expect: variant: "C", ui.version: "v3", backgroundColor: "#0d1117"


### Update Config Without Redeployment (Scenario 3 Only)

bash
# Change V3 to 20%, update V3 color to green
aws dynamodb update-item \
  --table-name ab-test-config \
  --key '{"testId": {"S": "profile-ui"}}' \
  --update-expression "SET variants[2].weight = :w, variants[2].ui.accentColor = :c, updatedAt = :t" \
  --expression-attribute-values '{
    ":w": {"N": "20"},
    ":c": {"S": "#2ea043"},
    ":t": {"S": "2026-02-11T15:00:00Z"}
  }' \
  --region us-east-1

# Also adjust other weights to total 100
aws dynamodb update-item \
  --table-name ab-test-config \
  --key '{"testId": {"S": "profile-ui"}}' \
  --update-expression "SET variants[0].weight = :wa, variants[1].weight = :wb" \
  --expression-attribute-values '{
    ":wa": {"N": "40"},
    ":wb": {"N": "40"}
  }' \
  --region us-east-1

# Changes take effect within 60 seconds (Lambda cache TTL)
# No redeployment needed
# Invalidate CloudFront cache to apply to existing cached responses
aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/api/profile/*"


This is the key advantage of Scenario 3 - change weights, colors, layout, and add new variants entirely from DynamoDB without 
touching any code or redeploying anything.
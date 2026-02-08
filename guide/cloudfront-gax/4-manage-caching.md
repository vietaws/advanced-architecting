## Managing API Caching in CloudFront

### Overview

CloudFront caches based on:
1. URL path
2. Query strings
3. Headers
4. Cookies

You control caching through Cache Behaviors and Cache Policies.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Option 1: CloudFront + ALB

### Step 1: Create CloudFront Distribution with ALB Origin

bash
aws cloudfront create-distribution \
  --origin-domain-name my-alb-123.us-east-1.elb.amazonaws.com \
  --default-root-object index.html


### Step 2: Configure Cache Behavior for API Endpoints

json
{
  "Origins": [{
    "Id": "alb-origin",
    "DomainName": "my-alb-123.us-east-1.elb.amazonaws.com",
    "CustomOriginConfig": {
      "HTTPPort": 80,
      "HTTPSPort": 443,
      "OriginProtocolPolicy": "https-only"
    }
  }],
  "CacheBehaviors": {
    "Quantity": 3,
    "Items": [
      {
        "PathPattern": "/api/products",
        "TargetOriginId": "alb-origin",
        "ViewerProtocolPolicy": "https-only",
        "AllowedMethods": {
          "Quantity": 2,
          "Items": ["GET", "HEAD"]
        },
        "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
        "MinTTL": 300,
        "DefaultTTL": 3600,
        "MaxTTL": 86400
      },
      {
        "PathPattern": "/api/user/*",
        "TargetOriginId": "alb-origin",
        "ViewerProtocolPolicy": "https-only",
        "AllowedMethods": {
          "Quantity": 7,
          "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
        },
        "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
        "MinTTL": 0,
        "DefaultTTL": 0,
        "MaxTTL": 0
      },
      {
        "PathPattern": "/static/*",
        "TargetOriginId": "alb-origin",
        "ViewerProtocolPolicy": "https-only",
        "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
        "MinTTL": 86400,
        "DefaultTTL": 86400,
        "MaxTTL": 31536000
      }
    ]
  }
}


### Step 3: ALB Returns Cache-Control Headers

javascript
// Express.js on EC2 behind ALB
const express = require('express');
const app = express();

// Cacheable endpoint (product list)
app.get('/api/products', (req, res) => {
  res.set({
    'Cache-Control': 'public, max-age=3600',  // Cache for 1 hour
    'Content-Type': 'application/json'
  });
  
  res.json([
    { id: 1, name: 'Product 1', price: 100 },
    { id: 2, name: 'Product 2', price: 200 }
  ]);
});

// Non-cacheable endpoint (user profile)
app.get('/api/user/profile', (req, res) => {
  res.set({
    'Cache-Control': 'private, no-cache, no-store, must-revalidate',
    'Content-Type': 'application/json'
  });
  
  res.json({
    id: req.user.id,
    name: req.user.name,
    email: req.user.email
  });
});

// Cacheable with query string
app.get('/api/products/search', (req, res) => {
  const category = req.query.category;
  
  res.set({
    'Cache-Control': 'public, max-age=1800',  // Cache for 30 minutes
    'Vary': 'Accept-Encoding'
  });
  
  res.json(searchProducts(category));
});

app.listen(3000);


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Option 2: CloudFront + API Gateway

### Step 1: Create API Gateway

bash
# Create REST API
aws apigateway create-rest-api \
  --name my-api \
  --endpoint-configuration types=REGIONAL


### Step 2: Enable API Gateway Caching (Optional)

bash
# Create deployment with cache
aws apigateway create-deployment \
  --rest-api-id abc123 \
  --stage-name prod \
  --cache-cluster-enabled \
  --cache-cluster-size 0.5


Note: API Gateway caching is separate from CloudFront caching!

### Step 3: Configure CloudFront with API Gateway Origin

json
{
  "Origins": [{
    "Id": "api-gateway-origin",
    "DomainName": "abc123.execute-api.us-east-1.amazonaws.com",
    "OriginPath": "/prod",
    "CustomOriginConfig": {
      "HTTPSPort": 443,
      "OriginProtocolPolicy": "https-only",
      "OriginSslProtocols": {
        "Quantity": 1,
        "Items": ["TLSv1.2"]
      }
    }
  }],
  "CacheBehaviors": {
    "Quantity": 2,
    "Items": [
      {
        "PathPattern": "/products",
        "TargetOriginId": "api-gateway-origin",
        "ViewerProtocolPolicy": "https-only",
        "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
        "MinTTL": 300,
        "DefaultTTL": 3600,
        "MaxTTL": 86400,
        "ForwardedValues": {
          "QueryString": true,
          "Headers": {
            "Quantity": 1,
            "Items": ["Authorization"]
          }
        }
      },
      {
        "PathPattern": "/user/*",
        "TargetOriginId": "api-gateway-origin",
        "ViewerProtocolPolicy": "https-only",
        "MinTTL": 0,
        "DefaultTTL": 0,
        "MaxTTL": 0
      }
    ]
  }
}


### Step 4: API Gateway Lambda Returns Cache Headers

javascript
// Lambda function behind API Gateway
exports.handler = async (event) => {
  // Cacheable response
  if (event.path === '/products') {
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'public, max-age=3600'
      },
      body: JSON.stringify([
        { id: 1, name: 'Product 1' },
        { id: 2, name: 'Product 2' }
      ])
    };
  }
  
  // Non-cacheable response
  if (event.path.startsWith('/user/')) {
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'private, no-cache'
      },
      body: JSON.stringify({
        id: event.requestContext.authorizer.userId,
        name: 'John Doe'
      })
    };
  }
};


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cache Control Strategies

### 1. Cacheable Public Data (Product Catalog)

javascript
// ALB/API Gateway response
res.set({
  'Cache-Control': 'public, max-age=3600',  // 1 hour
  'ETag': '"abc123"'
});


CloudFront behavior:
Request 1: User → CloudFront → Origin (cache miss)
Request 2-N: User → CloudFront (cache hit for 1 hour)

Origin requests: 1 per hour
Cache hit rate: 99%


### 2. Non-Cacheable Private Data (User Profile)

javascript
// ALB/API Gateway response
res.set({
  'Cache-Control': 'private, no-cache, no-store, must-revalidate',
  'Pragma': 'no-cache',
  'Expires': '0'
});


CloudFront behavior:
Every request goes to origin
Cache hit rate: 0%


### 3. Cacheable with Query String (Search)

javascript
// ALB/API Gateway response for /api/products?category=electronics
res.set({
  'Cache-Control': 'public, max-age=1800',  // 30 minutes
  'Vary': 'Accept-Encoding'
});


CloudFront configuration:
json
{
  "ForwardedValues": {
    "QueryString": true,
    "QueryStringCacheKeys": {
      "Quantity": 1,
      "Items": ["category"]
    }
  }
}


CloudFront behavior:
/api/products?category=electronics → Cached separately
/api/products?category=books → Cached separately
/api/products?category=electronics → Cache hit


### 4. Cacheable with Authorization (Per-User)

javascript
// ALB/API Gateway response
res.set({
  'Cache-Control': 'private, max-age=300',  // 5 minutes
  'Vary': 'Authorization'
});


CloudFront configuration:
json
{
  "ForwardedValues": {
    "Headers": {
      "Quantity": 1,
      "Items": ["Authorization"]
    }
  }
}


CloudFront behavior:
User A (token: abc) → Cached separately
User B (token: xyz) → Cached separately
User A (token: abc) → Cache hit


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Example: E-commerce API

### CloudFront Configuration

json
{
  "CacheBehaviors": {
    "Items": [
      {
        "PathPattern": "/api/products",
        "MinTTL": 3600,
        "DefaultTTL": 3600,
        "MaxTTL": 86400,
        "ForwardedValues": {
          "QueryString": true,
          "QueryStringCacheKeys": {
            "Items": ["category", "page"]
          }
        }
      },
      {
        "PathPattern": "/api/products/*",
        "MinTTL": 3600,
        "DefaultTTL": 3600,
        "MaxTTL": 86400
      },
      {
        "PathPattern": "/api/cart",
        "MinTTL": 0,
        "DefaultTTL": 0,
        "MaxTTL": 0,
        "ForwardedValues": {
          "Headers": {
            "Items": ["Authorization", "Cookie"]
          }
        }
      },
      {
        "PathPattern": "/api/checkout",
        "MinTTL": 0,
        "DefaultTTL": 0,
        "MaxTTL": 0,
        "AllowedMethods": {
          "Items": ["POST"]
        }
      }
    ]
  }
}


### ALB Backend

javascript
const express = require('express');
const app = express();

// Public product list (cacheable)
app.get('/api/products', (req, res) => {
  res.set('Cache-Control', 'public, max-age=3600');
  res.json(getProducts(req.query.category));
});

// Public product detail (cacheable)
app.get('/api/products/:id', (req, res) => {
  res.set('Cache-Control', 'public, max-age=3600');
  res.json(getProduct(req.params.id));
});

// User cart (not cacheable)
app.get('/api/cart', authenticate, (req, res) => {
  res.set('Cache-Control', 'private, no-cache');
  res.json(getCart(req.user.id));
});

// Checkout (not cacheable)
app.post('/api/checkout', authenticate, (req, res) => {
  res.set('Cache-Control', 'no-store');
  res.json(processCheckout(req.user.id, req.body));
});

app.listen(3000);


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cache Invalidation

### Method 1: CloudFront Invalidation

bash
# Invalidate specific paths
aws cloudfront create-invalidation \
  --distribution-id E1234 \
  --paths "/api/products" "/api/products/*"

# Invalidate all
aws cloudfront create-invalidation \
  --distribution-id E1234 \
  --paths "/*"


Cost: First 1,000 invalidations/month free, then $0.005 per path

### Method 2: Versioned URLs

javascript
// Instead of: /api/products
// Use: /api/products?v=2

app.get('/api/products', (req, res) => {
  const version = req.query.v || '1';
  res.set('Cache-Control', 'public, max-age=31536000');  // 1 year
  res.json(getProducts(version));
});

// When data changes, increment version
// Old: /api/products?v=1 (still cached)
// New: /api/products?v=2 (new cache entry)


### Method 3: Cache-Control Headers

javascript
// Origin can control cache duration
app.get('/api/products', (req, res) => {
  if (productsUpdated) {
    res.set('Cache-Control', 'public, max-age=60');  // Short TTL
  } else {
    res.set('Cache-Control', 'public, max-age=3600');  // Long TTL
  }
  res.json(getProducts());
});


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Monitoring Cache Performance

bash
# CloudFront cache statistics
aws cloudwatch get-metric-statistics \
  --namespace AWS/CloudFront \
  --metric-name CacheHitRate \
  --dimensions Name=DistributionId,Value=E1234 \
  --start-time 2026-02-08T00:00:00Z \
  --end-time 2026-02-08T21:00:00Z \
  --period 3600 \
  --statistics Average

# Origin requests (lower is better)
aws cloudwatch get-metric-statistics \
  --namespace AWS/CloudFront \
  --metric-name Requests \
  --dimensions Name=DistributionId,Value=E1234 Name=Region,Value=Global \
  --start-time 2026-02-08T00:00:00Z \
  --end-time 2026-02-08T21:00:00Z \
  --period 3600 \
  --statistics Sum


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

### Caching Strategy

| Endpoint | Cache | TTL | Headers |
|----------|-------|-----|---------|
| GET /api/products | ✅ Yes | 1 hour | Cache-Control: public, max-age=3600 |
| GET /api/products/:id | ✅ Yes | 1 hour | Cache-Control: public, max-age=3600 |
| GET /api/products?category=X | ✅ Yes | 30 min | Cache-Control: public, max-age=1800 |
| GET /api/user/profile | ❌ No | 0 | Cache-Control: private, no-cache |
| GET /api/cart | ❌ No | 0 | Cache-Control: private, no-cache |
| POST /api/checkout | ❌ No | 0 | Cache-Control: no-store |

### Key Points

1. Use Cache-Control headers from origin (ALB/API Gateway)
2. Configure CloudFront cache behaviors per path pattern
3. Forward query strings for search/filter endpoints
4. Don't cache personalized or write operations
5. Use versioned URLs instead of invalidations
6. Monitor cache hit rate (target >80%)

Best practice: Let origin control caching with Cache-Control headers, CloudFront respects them.
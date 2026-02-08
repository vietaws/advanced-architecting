## Two-Layer Caching: CloudFront + API Gateway

### Quick Answer

Edge-Optimized API Gateway:
- CloudFront is automatic, but caching is OFF by default
- You must configure caching at both layers separately
- CloudFront caching requires custom configuration
- API Gateway caching requires explicit enablement

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Default Behavior (No Caching)

User → CloudFront Edge (no cache) → API Gateway (no cache) → Lambda
       Every request hits Lambda


Edge-Optimized creates CloudFront distribution automatically, but:
- CloudFront passes all requests through (no caching)
- API Gateway doesn't cache responses
- Every request invokes Lambda

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Two-Layer Caching Architecture

User → CloudFront Edge (cache: 60s) → API Gateway (cache: 300s) → Lambda
       ↓                               ↓
       Cache HIT (60s)                 Cache HIT (300s)
       Return immediately              Return immediately
       
       Cache MISS                      Cache MISS
       Forward to API Gateway          Invoke Lambda


Benefits:
- **Layer 1 (CloudFront):** Fast edge caching, reduces API Gateway requests
- **Layer 2 (API Gateway):** Regional caching, reduces Lambda invocations

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Configuration

### Layer 1: CloudFront Caching

Problem: Edge-Optimized API Gateway creates CloudFront automatically, but you cannot configure it directly.

Solution: Use custom domain with your own CloudFront distribution.

#### Step 1: Create Regional API (not Edge-Optimized)

bash
# Create Regional API instead
aws apigateway create-rest-api \
  --name products-api \
  --endpoint-configuration types=REGIONAL

API_ID=abc123

# Configure API resources and methods...
# (Same as before)

# Deploy
aws apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name prod


#### Step 2: Create CloudFront Distribution with Caching

bash
# Create CloudFront distribution
cat > cloudfront-config.json <<EOF
{
  "CallerReference": "$(date +%s)",
  "Comment": "API Gateway with caching",
  "Enabled": true,
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "api-gateway-origin",
        "DomainName": "$API_ID.execute-api.us-east-1.amazonaws.com",
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
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "api-gateway-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 7,
      "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["GET", "HEAD"]
      }
    },
    "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
    "OriginRequestPolicyId": "b689b0a8-53d0-40ab-baf2-68738e2966ac",
    "Compress": true,
    "MinTTL": 0,
    "DefaultTTL": 60,
    "MaxTTL": 300
  }
}
EOF

aws cloudfront create-distribution \
  --distribution-config file://cloudfront-config.json


Simpler approach with CLI:

bash
aws cloudfront create-distribution \
  --origin-domain-name $API_ID.execute-api.us-east-1.amazonaws.com \
  --origin-path /prod \
  --default-root-object "" \
  --comment "API with caching" \
  --enabled \
  --default-cache-behavior \
    TargetOriginId=api-gateway,\
    ViewerProtocolPolicy=redirect-to-https,\
    AllowedMethods=GET,HEAD,OPTIONS,PUT,POST,PATCH,DELETE,\
    CachedMethods=GET,HEAD,\
    MinTTL=0,\
    DefaultTTL=60,\
    MaxTTL=300,\
    ForwardedValues={QueryString=true,Headers={Quantity=1,Items=[Authorization]}}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Layer 2: API Gateway Caching

bash
# Enable caching on API Gateway stage
aws apigateway create-stage \
  --rest-api-id $API_ID \
  --stage-name prod \
  --deployment-id $DEPLOYMENT_ID \
  --cache-cluster-enabled \
  --cache-cluster-size "0.5"

# Configure cache settings
aws apigateway update-stage \
  --rest-api-id $API_ID \
  --stage-name prod \
  --patch-operations \
    op=replace,path=/cacheClusterEnabled,value=true \
    op=replace,path=/cacheClusterSize,value=0.5 \
    op=replace,path=/*/*/caching/ttlInSeconds,value=300 \
    op=replace,path=/*/*/caching/dataEncrypted,value=true


Cache sizes:
- 0.5 GB: $0.020/hour ($14.40/month)
- 1.6 GB: $0.038/hour ($27.36/month)
- 6.1 GB: $0.200/hour ($144/month)
- 13.5 GB: $0.250/hour ($180/month)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Example: Two-Layer Caching

### Lambda Function (with Cache-Control headers)

javascript
exports.handler = async (event) => {
  const productId = event.pathParameters?.id;
  
  // Simulate database query
  const product = {
    id: productId,
    name: 'Product ' + productId,
    price: 99.99,
    timestamp: new Date().toISOString()
  };
  
  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'public, max-age=60', // CloudFront: 60s
      'Access-Control-Allow-Origin': '*'
    },
    body: JSON.stringify(product)
  };
};


### API Gateway Method with Caching

bash
# Create method
aws apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method GET \
  --authorization-type NONE \
  --request-parameters method.request.path.id=true

# Enable caching for this method
aws apigateway put-method-response \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method GET \
  --status-code 200 \
  --response-parameters \
    method.response.header.Cache-Control=true

# Configure integration
aws apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:ACCOUNT:function:get-product/invocations \
  --cache-key-parameters method.request.path.id

# Configure cache settings for method
aws apigateway update-method \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method GET \
  --patch-operations \
    op=replace,path=/caching/ttlInSeconds,value=300 \
    op=replace,path=/caching/enabled,value=true


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cache Key Configuration

### CloudFront Cache Key

Include in cache key:
json
{
  "QueryStrings": {
    "QueryStringBehavior": "all"
  },
  "Headers": {
    "HeaderBehavior": "whitelist",
    "Headers": {
      "Items": ["Authorization", "Accept-Language"]
    }
  },
  "Cookies": {
    "CookieBehavior": "none"
  }
}


Example: Different cache for each user
User A (Authorization: Bearer token-A) → Cached separately
User B (Authorization: Bearer token-B) → Cached separately


### API Gateway Cache Key

bash
# Cache by path parameter
aws apigateway put-integration \
  --cache-key-parameters method.request.path.id

# Cache by query parameter
aws apigateway put-integration \
  --cache-key-parameters method.request.querystring.category

# Cache by multiple parameters
aws apigateway put-integration \
  --cache-key-parameters \
    method.request.path.id \
    method.request.querystring.sort


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Best Practices

### 1. Cache TTL Strategy

CloudFront TTL < API Gateway TTL < Data freshness requirement

Example:
- CloudFront: 60s (fast edge response)
- API Gateway: 300s (reduce Lambda invocations)
- Database: Update every 10 minutes


Why?
- CloudFront expires first → requests hit API Gateway cache
- API Gateway cache still valid → no Lambda invocation
- After 300s → Lambda invoked, both caches refreshed

### 2. Cache-Control Headers

javascript
// Static content (rarely changes)
headers: {
  'Cache-Control': 'public, max-age=3600, s-maxage=3600'
}
// CloudFront: 3600s, API Gateway: use stage setting

// Dynamic content (changes frequently)
headers: {
  'Cache-Control': 'public, max-age=60, s-maxage=60'
}
// CloudFront: 60s, API Gateway: use stage setting

// User-specific content
headers: {
  'Cache-Control': 'private, max-age=300'
}
// CloudFront: cache per user, API Gateway: 300s

// No caching
headers: {
  'Cache-Control': 'no-cache, no-store, must-revalidate'
}
// Both layers: no caching


### 3. Cache Invalidation

CloudFront:
bash
# Invalidate specific path
aws cloudfront create-invalidation \
  --distribution-id E1234567890ABC \
  --paths "/products/*"

# Invalidate all
aws cloudfront create-invalidation \
  --distribution-id E1234567890ABC \
  --paths "/*"

# Cost: First 1000 paths/month free, then $0.005 per path


API Gateway:
bash
# Flush entire cache
aws apigateway flush-stage-cache \
  --rest-api-id $API_ID \
  --stage-name prod

# Invalidate specific cache key (requires custom implementation)
# Use cache key parameter in request with special header


### 4. Conditional Caching

Cache only successful responses:

javascript
exports.handler = async (event) => {
  try {
    const data = await getDataFromDB();
    
    return {
      statusCode: 200,
      headers: {
        'Cache-Control': 'public, max-age=300' // Cache success
      },
      body: JSON.stringify(data)
    };
  } catch (error) {
    return {
      statusCode: 500,
      headers: {
        'Cache-Control': 'no-cache' // Don't cache errors
      },
      body: JSON.stringify({ error: 'Internal error' })
    };
  }
};


### 5. Cache Monitoring

bash
# CloudFront cache hit ratio
aws cloudwatch get-metric-statistics \
  --namespace AWS/CloudFront \
  --metric-name CacheHitRate \
  --dimensions Name=DistributionId,Value=E1234567890ABC \
  --start-time 2026-02-08T00:00:00Z \
  --end-time 2026-02-09T00:00:00Z \
  --period 3600 \
  --statistics Average

# API Gateway cache hits/misses
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name CacheHitCount \
  --dimensions Name=ApiName,Value=products-api,Name=Stage,Value=prod \
  --start-time 2026-02-08T00:00:00Z \
  --end-time 2026-02-09T00:00:00Z \
  --period 3600 \
  --statistics Sum


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Caching Decision Matrix

| Scenario | CloudFront TTL | API Gateway TTL | Cache Key |
|----------|----------------|-----------------|-----------|
| Public product list | 300s | 600s | None |
| User-specific data | 60s | 300s | Authorization header |
| Search results | 120s | 300s | Query parameters |
| Real-time data | 0s (disabled) | 0s (disabled) | N/A |
| Static content | 3600s | 3600s | None |
| Paginated results | 180s | 300s | page, limit params |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Optimization

### Without Caching
1M requests/month
- API Gateway: 1M × $3.50 = $3.50
- Lambda: 1M × $0.20 = $0.20
- CloudFront: 1M × $0.0075/10K = $0.75
Total: $4.45/month


### With Two-Layer Caching (80% hit rate)
1M requests/month
- CloudFront: 1M × $0.0075/10K = $0.75
- API Gateway: 200K × $3.50 = $0.70 (80% cached at CloudFront)
- API Gateway cache: 0.5GB × $0.020/hour × 730 = $14.60
- Lambda: 40K × $0.20 = $0.008 (80% cached at API Gateway)
Total: $16.06/month

Savings on Lambda: $0.19/month (95% reduction in invocations)
Trade-off: Pay $11.61 more for caching infrastructure


Worth it when:
- High traffic (>10M requests/month)
- Expensive Lambda execution (>100ms)
- Global users (latency improvement)
- Database load reduction needed

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

Two-layer caching setup:

1. Use Regional API (not Edge-Optimized) for control
2. Create custom CloudFront distribution with caching enabled
3. Enable API Gateway caching on stage
4. Set Cache-Control headers in Lambda responses
5. Configure cache keys for both layers
6. Monitor cache hit rates and adjust TTLs
7. Implement invalidation strategy for updates

Key insight: Edge-Optimized API Gateway includes CloudFront but doesn't enable caching by default. For full control, use 
Regional API + custom CloudFront distribution.
## API Gateway: Regional vs Edge-Optimized

### Quick Comparison

| Feature | Regional | Edge-Optimized |
|---------|----------|----------------|
| Architecture | Single region | CloudFront + Single region |
| Global Distribution | ❌ No | ✅ Yes (via CloudFront) |
| Latency | Higher for distant users | Lower globally |
| Custom Domain | Your CloudFront/CDN | AWS CloudFront (automatic) |
| Pricing | API Gateway only | API Gateway + CloudFront |
| TLS Termination | At API Gateway | At CloudFront edge |
| DDoS Protection | Standard | AWS Shield (CloudFront) |
| Caching | API Gateway cache | CloudFront + API Gateway cache |
| Use Case | Regional apps | Global apps |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Architecture

### Regional API

User (Tokyo) → Internet → API Gateway (us-east-1) → Lambda
             (Long distance)

Latency: 150-300ms (depends on distance)


Components:
- API Gateway endpoint in single region
- Direct connection from users
- No CloudFront

Endpoint format:
https://abc123.execute-api.us-east-1.amazonaws.com/prod


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Edge-Optimized API

User (Tokyo) → CloudFront Edge (Tokyo) → API Gateway (us-east-1) → Lambda
              (Short distance)         (AWS backbone)

Latency: 50-100ms (faster)


Components:
- API Gateway endpoint in single region
- CloudFront distribution (automatic)
- Requests routed through nearest edge location

Endpoint format:
https://abc123.execute-api.us-east-1.amazonaws.com/prod
(Same format, but uses CloudFront behind the scenes)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Detailed Architecture

### Regional API

┌─────────────────────────────────────────────────────────┐
│ User (Tokyo)                                             │
└─────────────────────────────────────────────────────────┘
                          ↓
                  Public Internet
                  (150-300ms latency)
                          ↓
┌─────────────────────────────────────────────────────────┐
│ API Gateway (us-east-1)                                  │
│ https://abc123.execute-api.us-east-1.amazonaws.com      │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Lambda (us-east-1)                                       │
└─────────────────────────────────────────────────────────┘


### Edge-Optimized API

┌─────────────────────────────────────────────────────────┐
│ User (Tokyo)                                             │
└─────────────────────────────────────────────────────────┘
                          ↓
                  (10-20ms latency)
                          ↓
┌─────────────────────────────────────────────────────────┐
│ CloudFront Edge Location (Tokyo)                         │
│ - TLS termination                                        │
│ - DDoS protection                                        │
│ - Optional caching                                       │
└─────────────────────────────────────────────────────────┘
                          ↓
                  AWS Backbone Network
                  (50-80ms latency)
                          ↓
┌─────────────────────────────────────────────────────────┐
│ API Gateway (us-east-1)                                  │
│ https://abc123.execute-api.us-east-1.amazonaws.com      │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Lambda (us-east-1)                                       │
└─────────────────────────────────────────────────────────┘

Total latency: 60-100ms (vs 150-300ms for Regional)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Pricing

### Regional API

API Gateway Charges:
- First 333M requests: $3.50 per million
- Next 667M requests: $2.80 per million
- Over 1B requests: $2.38 per million

Example (1M requests/month):
- API Gateway: 1M × $3.50 = $3.50
- Data transfer: $0.09/GB
- Total: $3.50 + data transfer

No CloudFront charges


### Edge-Optimized API

API Gateway Charges: Same as Regional
- $3.50 per million requests

CloudFront Charges (Additional):
- Data transfer: $0.085/GB (first 10TB)
- Requests: $0.0075 per 10,000 requests

Example (1M requests/month, 10GB data):
- API Gateway: $3.50
- CloudFront data: 10GB × $0.085 = $0.85
- CloudFront requests: (1M / 10K) × $0.0075 = $0.75
- Total: $5.10

~45% more expensive than Regional


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Latency Comparison

### Test from Different Locations

Regional API (us-east-1):
User Location    Latency to API Gateway
us-east-1        10-20ms
us-west-2        70-90ms
eu-west-1        80-100ms
ap-southeast-1   180-220ms
ap-northeast-1   150-180ms


Edge-Optimized API:
User Location    Latency to Edge    Edge to API    Total
us-east-1        5-10ms            10-20ms        15-30ms
us-west-2        5-10ms            50-70ms        55-80ms
eu-west-1        5-10ms            70-90ms        75-100ms
ap-southeast-1   5-10ms            100-120ms      105-130ms
ap-northeast-1   5-10ms            90-110ms       95-120ms

Improvement: 30-50% lower latency for distant users


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Features

### Regional API

Advantages:
✅ Lower cost (no CloudFront)
✅ Simpler architecture
✅ Direct connection
✅ Easier debugging
✅ No CloudFront propagation delay

Disadvantages:
❌ Higher latency for distant users
❌ No automatic DDoS protection
❌ No edge caching
❌ Single TLS termination point

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Edge-Optimized API

Advantages:
✅ Lower latency globally
✅ CloudFront DDoS protection (AWS Shield)
✅ TLS termination at edge
✅ Optional edge caching
✅ Better for global users

Disadvantages:
❌ Higher cost (~45% more)
❌ More complex architecture
❌ CloudFront propagation delay (5-10 minutes)
❌ Harder to debug (extra layer)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Use Cases

### Use Regional API When:

✅ Users in same region
Example: US-only application
- All users in US
- API Gateway in us-east-1
- No need for global distribution


✅ Cost-sensitive
Startup with limited budget
- Save 45% on API costs
- Users can tolerate slightly higher latency


✅ Internal APIs
Microservices communication
- Services in same region
- No external users


✅ Development/Testing
Dev/staging environments
- No need for global distribution
- Faster deployment (no CloudFront propagation)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Use Edge-Optimized API When:

✅ Global user base
Example: International SaaS application
- Users in US, Europe, Asia
- Need consistent low latency
- Worth the extra cost


✅ Mobile apps
Mobile app with users worldwide
- Users expect fast response
- Better user experience


✅ Public APIs
Third-party API integrations
- Unknown user locations
- Need DDoS protection


✅ High-value transactions
E-commerce checkout API
- Latency affects conversion
- Extra cost justified by revenue


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Create Each Type

### Create Regional API

bash
aws apigateway create-rest-api \
  --name my-regional-api \
  --endpoint-configuration types=REGIONAL

# Endpoint:
# https://abc123.execute-api.us-east-1.amazonaws.com/prod


### Create Edge-Optimized API

bash
aws apigateway create-rest-api \
  --name my-edge-api \
  --endpoint-configuration types=EDGE

# Endpoint (same format, but uses CloudFront):
# https://def456.execute-api.us-east-1.amazonaws.com/prod


### Convert Regional to Edge-Optimized

bash
aws apigateway update-rest-api \
  --rest-api-id abc123 \
  --patch-operations op=replace,path=/endpointConfiguration/types/REGIONAL,value=EDGE


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Custom Domain

### Regional API with Custom Domain

bash
# Create custom domain
aws apigateway create-domain-name \
  --domain-name api.example.com \
  --regional-certificate-arn arn:aws:acm:us-east-1:ACCOUNT:certificate/xxxxx \
  --endpoint-configuration types=REGIONAL

# Get regional domain name
REGIONAL_DOMAIN=$(aws apigateway get-domain-name \
  --domain-name api.example.com \
  --query 'regionalDomainName' \
  --output text)

# Create Route 53 record
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123 \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "api.example.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z1234567890ABC",
          "DNSName": "'$REGIONAL_DOMAIN'",
          "EvaluateTargetHealth": false
        }
      }
    }]
  }'


### Edge-Optimized API with Custom Domain

bash
# Create custom domain (uses CloudFront automatically)
aws apigateway create-domain-name \
  --domain-name api.example.com \
  --certificate-arn arn:aws:acm:us-east-1:ACCOUNT:certificate/xxxxx \
  --endpoint-configuration types=EDGE

# Get CloudFront distribution domain
CLOUDFRONT_DOMAIN=$(aws apigateway get-domain-name \
  --domain-name api.example.com \
  --query 'distributionDomainName' \
  --output text)

# Create Route 53 record (points to CloudFront)
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123 \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "api.example.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z2FDTNDATAQYW2",
          "DNSName": "'$CLOUDFRONT_DOMAIN'",
          "EvaluateTargetHealth": false
        }
      }
    }]
  }'


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Caching

### Regional API

Only API Gateway caching:
bash
# Enable caching
aws apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name prod \
  --cache-cluster-enabled \
  --cache-cluster-size 0.5

# Cost: $0.02/hour = $14.40/month (0.5 GB cache)


### Edge-Optimized API

Two layers of caching:
1. CloudFront edge caching (automatic, free)
2. API Gateway caching (optional, paid)

Benefits:
- CloudFront caches at edge (closer to users)
- API Gateway caches at origin (reduces Lambda invocations)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

### Decision Matrix

| Scenario | Choose |
|----------|--------|
| Users in single region | Regional |
| Users worldwide | Edge-Optimized |
| Cost-sensitive | Regional |
| Need low latency globally | Edge-Optimized |
| Internal/private API | Regional (or Private) |
| Public API | Edge-Optimized |
| Development/testing | Regional |
| Production (global) | Edge-Optimized |
| Need DDoS protection | Edge-Optimized |
| Simple architecture | Regional |

### Key Differences

Regional:
- Direct connection
- Single region
- Lower cost
- Higher latency for distant users

Edge-Optimized:
- CloudFront distribution
- Global edge locations
- Higher cost (~45% more)
- Lower latency globally

Most common choice: Edge-Optimized (default) for production, Regional for development or regional-only applications.
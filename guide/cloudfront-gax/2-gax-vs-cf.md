## Global Accelerator vs CloudFront

### Quick Comparison

| Feature | CloudFront | Global Accelerator |
|---------|------------|-------------------|
| Purpose | Content delivery (CDN) | Network acceleration |
| Layer | Layer 7 (HTTP/HTTPS) | Layer 4 (TCP/UDP) |
| Caching | ✅ Yes (caches content) | ❌ No (proxies traffic) |
| Protocols | HTTP, HTTPS, WebSocket | TCP, UDP, HTTP, HTTPS |
| Static IPs | ❌ No (dynamic IPs) | ✅ Yes (2 static Anycast IPs) |
| Use Case | Static content, APIs, websites | Dynamic content, gaming, VoIP, non-HTTP |
| Pricing | Data transfer + requests | Hourly + data transfer |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## CloudFront (Content Delivery Network)

### What It Does

Caches content at edge locations worldwide

User (Tokyo)
  ↓
CloudFront Edge (Tokyo) ← Caches content
  ↓ (cache miss)
Origin (us-east-1)


### Key Features

1. Caching
- Stores static content at edge locations
- Reduces origin load
- Faster subsequent requests

2. Layer 7 (HTTP/HTTPS)
- Understands HTTP headers
- Can modify requests/responses
- URL-based routing

3. Dynamic IPs
- Each edge location has different IPs
- IPs can change

### Best For

✅ Static content (images, videos, CSS, JS)
✅ Websites with cacheable content
✅ APIs with caching
✅ Video streaming
✅ Software downloads
✅ Cost optimization (caching reduces origin traffic)

### Example Use Case

javascript
// Website with images
https://example.com/images/logo.png

Flow:
1. User requests logo.png
2. CloudFront checks cache
3. If cached: Returns from edge (fast, <10ms)
4. If not cached: Fetches from origin, caches, returns
5. Next user: Gets from cache (no origin request)

Result: 90% of requests served from cache


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Global Accelerator (Network Accelerator)

### What It Does

Routes traffic through AWS global network (no caching)

User (Tokyo)
  ↓
Global Accelerator Anycast IP
  ↓
AWS Edge Location (Tokyo)
  ↓
AWS Global Network (optimized routing)
  ↓
Origin (us-east-1)


### Key Features

1. No Caching
- Every request goes to origin
- Proxies traffic through AWS network

2. Layer 4 (TCP/UDP)
- Works with any protocol
- Doesn't understand HTTP

3. Static Anycast IPs
- 2 static IPs for your application
- Same IPs worldwide
- IPs never change

4. Health Checks & Failover
- Automatic failover between regions
- Traffic shifting

### Best For

✅ Dynamic content (personalized, real-time)
✅ Non-HTTP protocols (gaming, VoIP, MQTT)
✅ Applications requiring static IPs
✅ Multi-region active-active
✅ Low latency (consistent performance)
✅ TCP/UDP applications

### Example Use Case

javascript
// Real-time gaming server
TCP connection to game server

Flow:
1. User connects to static IP (3.5.6.7)
2. Global Accelerator routes to nearest edge
3. Traffic goes through AWS network
4. Reaches game server in us-east-1
5. Every packet goes through this path (no caching)

Result: 30-60% latency reduction vs public internet


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Detailed Comparison

### 1. Caching

CloudFront:
Request 1: User → CloudFront → Origin (200ms)
Request 2: User → CloudFront (cache hit, 10ms)
Request 3: User → CloudFront (cache hit, 10ms)

Origin requests: 1
Average latency: 73ms


Global Accelerator:
Request 1: User → GA → Origin (150ms)
Request 2: User → GA → Origin (150ms)
Request 3: User → GA → Origin (150ms)

Origin requests: 3
Average latency: 150ms


### 2. Protocols

CloudFront:
✅ HTTP
✅ HTTPS
✅ WebSocket
❌ TCP (non-HTTP)
❌ UDP
❌ Custom protocols


Global Accelerator:
✅ HTTP
✅ HTTPS
✅ TCP
✅ UDP
✅ Any TCP/UDP protocol


### 3. IP Addresses

CloudFront:
bash
# Dynamic IPs (change over time)
nslookup d1234.cloudfront.net

# Output:
# 54.192.1.1
# 54.192.1.2
# 54.192.1.3
# ... (many IPs, can change)


Global Accelerator:
bash
# Static Anycast IPs (never change)
aws globalaccelerator describe-accelerator \
  --accelerator-arn arn:aws:...

# Output:
# IpAddresses: [3.5.6.7, 3.5.6.8]
# These IPs NEVER change


### 4. Failover

CloudFront:
Active-Passive only
Primary origin fails → Secondary origin

Cannot do:
- Active-Active
- Traffic splitting
- Weighted routing


Global Accelerator:
Active-Active supported
├── us-east-1 (50% traffic)
└── eu-west-1 (50% traffic)

Can do:
- Active-Active
- Traffic splitting (0-100%)
- Weighted routing
- Instant failover (<30 seconds)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Use Case Examples

### Use Case 1: E-commerce Website

CloudFront (Better Choice):
Content:
- Product images (static)
- CSS/JS files (static)
- Product catalog (cacheable)
- API responses (cacheable with TTL)

Benefits:
- 90% cache hit rate
- Reduced origin load
- Lower costs
- Fast page loads

Cost: $0.085/GB (data transfer)


Global Accelerator (Not Ideal):
Content:
- Every request goes to origin
- No caching benefit
- Higher origin load
- Higher costs

Cost: $0.025/hour + $0.015/GB
Monthly: $18 + data transfer


Winner: CloudFront (caching saves money and improves performance)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Use Case 2: Real-Time Gaming

CloudFront (Not Suitable):
Protocol: TCP (custom game protocol)
Caching: Not applicable (real-time data)
Result: ❌ CloudFront doesn't support custom TCP


Global Accelerator (Perfect):
Protocol: TCP (any protocol)
Routing: Through AWS network
Latency: 30-60% reduction
Static IPs: Easy for players to connect

Benefits:
- Lower latency
- Consistent performance
- Static IPs for whitelisting
- Works with any protocol

Cost: $18/month + data transfer


Winner: Global Accelerator (only option for custom TCP)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Use Case 3: API with Dynamic Responses

CloudFront (Good for Some APIs):
GET /products → Cacheable (TTL: 5 minutes)
GET /user/profile → Not cacheable (personalized)
POST /orders → Not cacheable (write operation)

Cache hit rate: 40%
Cost: Lower (caching reduces origin traffic)


Global Accelerator (Good for Dynamic APIs):
All requests go to origin
No caching
Consistent low latency
Static IPs for IP whitelisting

Cache hit rate: 0%
Cost: Higher (all traffic to origin)


Winner: Depends
- Mostly read-only, cacheable → CloudFront
- Mostly dynamic, personalized → Global Accelerator

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Use Case 4: Video Streaming

CloudFront (Perfect):
Content: Video files (large, static)
Caching: Excellent (videos don't change)
Cost: Very low (cache hit rate >95%)

Example:
- 1TB video file
- 1 million views
- CloudFront: 1 origin fetch, 999,999 cache hits
- Cost: ~$85 (data transfer only)


Global Accelerator (Expensive):
Content: Video files
Caching: None (every view fetches from origin)
Cost: Very high

Example:
- 1TB video file
- 1 million views
- GA: 1 million origin fetches
- Cost: $18 + ~$15,000 (data transfer)


Winner: CloudFront (caching is essential for video)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Use Case 5: Multi-Region Active-Active

CloudFront (Limited):
Active-Passive only
Primary: us-east-1
Secondary: eu-west-1 (failover only)

Cannot split traffic 50/50


Global Accelerator (Excellent):
Active-Active
├── us-east-1 (50% traffic)
└── eu-west-1 (50% traffic)

Can adjust weights:
├── us-east-1 (70% traffic)
└── eu-west-1 (30% traffic)

Instant failover if region fails


Winner: Global Accelerator (true active-active)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Pricing Comparison

### CloudFront

Data Transfer: $0.085/GB (first 10TB)
Requests: $0.0075 per 10,000 requests

Example (1TB, 10M requests):
- Data: 1000 GB × $0.085 = $85
- Requests: (10M / 10K) × $0.0075 = $7.50
Total: $92.50/month


### Global Accelerator

Hourly: $0.025/hour = $18/month
Data Transfer: $0.015/GB (DT-Premium)

Example (1TB):
- Hourly: $18
- Data: 1000 GB × $0.015 = $15
Total: $33/month

Note: This is ADDITIONAL to origin data transfer costs


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## When to Use Each

### Use CloudFront When:

✅ Content is cacheable (static files, images, videos)
✅ HTTP/HTTPS only
✅ Want to reduce origin load
✅ Cost optimization is important
✅ Don't need static IPs
✅ Website or API with caching

### Use Global Accelerator When:

✅ Content is dynamic (personalized, real-time)
✅ Need non-HTTP protocols (TCP/UDP)
✅ Need static IPs (whitelisting, DNS)
✅ Multi-region active-active
✅ Gaming, VoIP, IoT applications
✅ Consistent low latency is critical

### Use Both When:

✅ CloudFront for static content
✅ Global Accelerator for dynamic/API traffic

Architecture:
├── CloudFront → S3 (static assets)
└── Global Accelerator → ALB (API)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

| Scenario | Choose |
|----------|--------|
| Website with images/videos | CloudFront |
| API with caching | CloudFront |
| Real-time gaming | Global Accelerator |
| VoIP application | Global Accelerator |
| Need static IPs | Global Accelerator |
| Multi-region active-active | Global Accelerator |
| Cost-sensitive | CloudFront |
| Dynamic personalized content | Global Accelerator |
| Video streaming | CloudFront |
| IoT (MQTT) | Global Accelerator |

Most common: CloudFront (90% of use cases benefit from caching)

Special cases: Global Accelerator (when caching doesn't help or need static IPs)
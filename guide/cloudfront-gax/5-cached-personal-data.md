## Cacheable with Authorization (Per-User Caching)

### The Challenge

Problem: You want to cache API responses, but each user sees different data.

User A requests /api/dashboard
→ Returns User A's dashboard

User B requests /api/dashboard
→ Should return User B's dashboard (not User A's cached data!)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## How Per-User Caching Works

### Key Concept: Cache by Authorization Header

CloudFront can cache separate copies for each unique Authorization header value.

Cache Key = URL + Authorization Header

User A (token: abc123):
/api/dashboard + Authorization: Bearer abc123 → Cache Entry 1

User B (token: xyz789):
/api/dashboard + Authorization: Bearer xyz789 → Cache Entry 2

User A again:
/api/dashboard + Authorization: Bearer abc123 → Cache Hit (Entry 1)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Implementation

### Step 1: CloudFront Configuration

json
{
  "CacheBehaviors": {
    "Items": [{
      "PathPattern": "/api/dashboard",
      "TargetOriginId": "alb-origin",
      "ViewerProtocolPolicy": "https-only",
      "AllowedMethods": {
        "Quantity": 2,
        "Items": ["GET", "HEAD"]
      },
      "CachePolicyId": "custom-auth-cache-policy",
      "MinTTL": 300,
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
    }]
  }
}


Key setting: "Items": ["Authorization"] - This makes CloudFront cache separately per Authorization header

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 2: Create Custom Cache Policy

bash
# Create cache policy that includes Authorization header
aws cloudfront create-cache-policy \
  --cache-policy-config '{
    "Name": "AuthorizationCachePolicy",
    "Comment": "Cache per user based on Authorization header",
    "DefaultTTL": 300,
    "MaxTTL": 600,
    "MinTTL": 60,
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
      "QueryStringsConfig": {
        "QueryStringBehavior": "none"
      },
      "CookiesConfig": {
        "CookieBehavior": "none"
      }
    }
  }'


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 3: Backend API (ALB/API Gateway)

javascript
const express = require('express');
const jwt = require('jsonwebtoken');

const app = express();

// Middleware to verify JWT token
function authenticate(req, res, next) {
  const authHeader = req.headers.authorization;
  
  if (!authHeader) {
    return res.status(401).json({ error: 'No authorization header' });
  }
  
  const token = authHeader.replace('Bearer ', '');
  
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.user = decoded;
    next();
  } catch (error) {
    return res.status(401).json({ error: 'Invalid token' });
  }
}

// Per-user cacheable endpoint
app.get('/api/dashboard', authenticate, (req, res) => {
  // Get user-specific data
  const dashboard = {
    userId: req.user.id,
    username: req.user.username,
    stats: getUserStats(req.user.id),
    recentActivity: getRecentActivity(req.user.id),
    notifications: getNotifications(req.user.id)
  };
  
  // Cache for 5 minutes per user
  res.set({
    'Cache-Control': 'private, max-age=300',
    'Vary': 'Authorization',
    'Content-Type': 'application/json'
  });
  
  res.json(dashboard);
});

app.listen(3000);


Important headers:
- Cache-Control: private - Indicates user-specific content
- Vary: Authorization - Tells CloudFront to cache separately per Authorization header

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## How It Works: Step-by-Step

### Scenario: 3 Users Access Same Endpoint

Time: 0s
User A (token: aaa111) → GET /api/dashboard
├── CloudFront: Cache miss (no entry for aaa111)
├── Forward to ALB with Authorization: Bearer aaa111
├── ALB: Returns User A's dashboard
├── CloudFront: Cache response (key: /api/dashboard + aaa111)
└── User A: Receives dashboard (200ms)

Time: 10s
User B (token: bbb222) → GET /api/dashboard
├── CloudFront: Cache miss (no entry for bbb222)
├── Forward to ALB with Authorization: Bearer bbb222
├── ALB: Returns User B's dashboard
├── CloudFront: Cache response (key: /api/dashboard + bbb222)
└── User B: Receives dashboard (200ms)

Time: 20s
User A (token: aaa111) → GET /api/dashboard
├── CloudFront: Cache HIT (found entry for aaa111)
├── Return cached User A's dashboard
└── User A: Receives dashboard (10ms) ← Fast!

Time: 30s
User C (token: ccc333) → GET /api/dashboard
├── CloudFront: Cache miss (no entry for ccc333)
├── Forward to ALB with Authorization: Bearer ccc333
├── ALB: Returns User C's dashboard
├── CloudFront: Cache response (key: /api/dashboard + ccc333)
└── User C: Receives dashboard (200ms)

Time: 40s
User B (token: bbb222) → GET /api/dashboard
├── CloudFront: Cache HIT (found entry for bbb222)
├── Return cached User B's dashboard
└── User B: Receives dashboard (10ms) ← Fast!


Result:
- 3 separate cache entries (one per user)
- Each user gets their own cached data
- No data leakage between users

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Example: User Dashboard API

### Frontend (React)

javascript
// React component
import { useState, useEffect } from 'react';

function Dashboard() {
  const [dashboard, setDashboard] = useState(null);
  const token = localStorage.getItem('authToken');
  
  useEffect(() => {
    fetch('https://d1234.cloudfront.net/api/dashboard', {
      headers: {
        'Authorization': `Bearer ${token}`
      }
    })
    .then(res => res.json())
    .then(data => setDashboard(data));
  }, [token]);
  
  if (!dashboard) return <div>Loading...</div>;
  
  return (
    <div>
      <h1>Welcome, {dashboard.username}</h1>
      <div>Total Orders: {dashboard.stats.orders}</div>
      <div>Total Spent: ${dashboard.stats.spent}</div>
    </div>
  );
}


### Backend (Express + ALB)

javascript
const express = require('express');
const jwt = require('jsonwebtoken');
const app = express();

// Authenticate middleware
function authenticate(req, res, next) {
  const token = req.headers.authorization?.replace('Bearer ', '');
  
  if (!token) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  
  try {
    req.user = jwt.verify(token, process.env.JWT_SECRET);
    next();
  } catch (error) {
    return res.status(401).json({ error: 'Invalid token' });
  }
}

// User dashboard (cached per user)
app.get('/api/dashboard', authenticate, async (req, res) => {
  const userId = req.user.id;
  
  // Fetch user-specific data from database
  const [stats, activity, notifications] = await Promise.all([
    db.query('SELECT COUNT(*) as orders, SUM(total) as spent FROM orders WHERE user_id = ?', [userId]),
    db.query('SELECT * FROM activity WHERE user_id = ? ORDER BY created_at DESC LIMIT 10', [userId]),
    db.query('SELECT * FROM notifications WHERE user_id = ? AND read = false', [userId])
  ]);
  
  const dashboard = {
    userId: userId,
    username: req.user.username,
    stats: {
      orders: stats[0].orders,
      spent: stats[0].spent
    },
    recentActivity: activity,
    notifications: notifications
  };
  
  // Cache for 5 minutes per user
  res.set({
    'Cache-Control': 'private, max-age=300',
    'Vary': 'Authorization',
    'Content-Type': 'application/json',
    'X-User-Id': userId  // For debugging
  });
  
  res.json(dashboard);
});

// User orders (cached per user)
app.get('/api/orders', authenticate, async (req, res) => {
  const orders = await db.query(
    'SELECT * FROM orders WHERE user_id = ? ORDER BY created_at DESC',
    [req.user.id]
  );
  
  res.set({
    'Cache-Control': 'private, max-age=600',  // 10 minutes
    'Vary': 'Authorization'
  });
  
  res.json(orders);
});

// User profile (cached per user)
app.get('/api/profile', authenticate, async (req, res) => {
  const profile = await db.query(
    'SELECT id, username, email, created_at FROM users WHERE id = ?',
    [req.user.id]
  );
  
  res.set({
    'Cache-Control': 'private, max-age=1800',  // 30 minutes
    'Vary': 'Authorization'
  });
  
  res.json(profile[0]);
});

app.listen(3000);


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cache Invalidation Per User

### Problem: User Updates Their Profile

User A updates profile
→ Cached dashboard still shows old data
→ Need to invalidate User A's cache (not all users!)


### Solution 1: Short TTL

javascript
// Use short cache duration for frequently updated data
res.set({
  'Cache-Control': 'private, max-age=60'  // 1 minute
});


### Solution 2: Versioned Tokens

javascript
// Include version in JWT token
const token = jwt.sign({
  id: user.id,
  username: user.username,
  version: user.profile_version  // Increment on update
}, secret);

// When user updates profile:
await db.query('UPDATE users SET profile_version = profile_version + 1 WHERE id = ?', [userId]);

// New token with new version → New cache entry


### Solution 3: CloudFront Invalidation (Expensive)

bash
# Invalidate specific user's cache (not possible directly)
# Must invalidate entire path
aws cloudfront create-invalidation \
  --distribution-id E1234 \
  --paths "/api/dashboard"

# This invalidates ALL users' cache (not ideal)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Security Considerations

### 1. Token Expiration

javascript
// JWT with expiration
const token = jwt.sign(
  { id: user.id, username: user.username },
  secret,
  { expiresIn: '1h' }  // Token expires in 1 hour
);

// Cache TTL should be <= token expiration
res.set({
  'Cache-Control': 'private, max-age=3600'  // Match token expiration
});


### 2. Prevent Cache Poisoning

javascript
// Validate token before caching
app.get('/api/dashboard', authenticate, (req, res) => {
  // authenticate middleware already verified token
  
  // Additional check: ensure user exists
  const user = await db.query('SELECT * FROM users WHERE id = ?', [req.user.id]);
  
  if (!user) {
    return res.status(401).json({ error: 'User not found' });
  }
  
  // Safe to cache
  res.set('Cache-Control', 'private, max-age=300');
  res.json(getDashboard(req.user.id));
});


### 3. Sensitive Data

javascript
// Don't cache highly sensitive data
app.get('/api/payment-methods', authenticate, (req, res) => {
  res.set({
    'Cache-Control': 'private, no-cache, no-store, must-revalidate'
  });
  
  res.json(getPaymentMethods(req.user.id));
});


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Performance Benefits

### Without Per-User Caching

1000 users, each requests dashboard 10 times/hour

Total requests to origin: 1000 × 10 = 10,000 req/hour
Database queries: 10,000 × 3 = 30,000 queries/hour
Average response time: 200ms


### With Per-User Caching (5 min TTL)

1000 users, each requests dashboard 10 times/hour
Cache TTL: 5 minutes (12 cache entries per hour per user)

Cache misses: 1000 × 12 = 12,000 req/hour
Cache hits: 10,000 - 12,000 = -2,000 (wait, math is wrong)

Correct calculation:
- Requests per user per hour: 10
- Cache duration: 5 minutes = 1/12 hour
- Cache misses per user per hour: 12
- But user only makes 10 requests/hour
- So: 10 requests, 1 cache miss, 9 cache hits

Total cache misses: 1000 × 1 = 1,000 req/hour
Total cache hits: 1000 × 9 = 9,000 req/hour
Cache hit rate: 90%

Origin requests: 1,000 (90% reduction!)
Database queries: 1,000 × 3 = 3,000 (90% reduction!)
Average response time: 20ms (10x faster)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Monitoring

bash
# Check cache hit rate
aws cloudwatch get-metric-statistics \
  --namespace AWS/CloudFront \
  --metric-name CacheHitRate \
  --dimensions Name=DistributionId,Value=E1234 \
  --start-time 2026-02-08T20:00:00Z \
  --end-time 2026-02-08T21:00:00Z \
  --period 300 \
  --statistics Average

# Check origin requests
aws cloudwatch get-metric-statistics \
  --namespace AWS/CloudFront \
  --metric-name OriginRequests \
  --dimensions Name=DistributionId,Value=E1234 \
  --start-time 2026-02-08T20:00:00Z \
  --end-time 2026-02-08T21:00:00Z \
  --period 300 \
  --statistics Sum


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

### Per-User Caching Setup

| Component | Configuration |
|-----------|---------------|
| CloudFront | Forward Authorization header |
| Cache Policy | Include Authorization in cache key |
| Backend | Return Cache-Control: private, max-age=X |
| Backend | Return Vary: Authorization |
| TTL | 1-10 minutes (balance freshness vs performance) |

### Key Points

1. Each user gets separate cache entry based on Authorization header
2. No data leakage between users
3. 90%+ cache hit rate for repeated requests
4. 10x faster response times for cache hits
5. 90% reduction in origin/database load
6. Use short TTL (1-10 minutes) for frequently updated data
7. Don't cache highly sensitive data (payment info, passwords)

Best for: User dashboards, user profiles, user orders, user settings - any user-specific data that doesn't change frequently.
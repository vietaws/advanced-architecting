## Scenario: E-commerce Application with Traffic Spikes

### Setup
- **Application**: Node.js on EC2
- **Database**: RDS PostgreSQL (db.t3.medium - 367 max connections)
- **Traffic**: Normal 100 req/s, Black Friday spike to 1,000 req/s

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Without RDS Proxy

### Architecture
50 EC2 instances → Direct connections → RDS PostgreSQL


### Application Code
javascript
const { Pool } = require('pg');

// Each EC2 instance creates its own pool
const pool = new Pool({
  host: 'my-db.xxxxx.us-east-1.rds.amazonaws.com',
  port: 5432,
  database: 'products_db',
  user: 'postgres',
  password: 'password',
  max: 20  // 20 connections per EC2
});

app.get('/products/:id', async (req, res) => {
  const result = await pool.query('SELECT * FROM products WHERE id = $1', [req.params.id]);
  res.json(result.rows[0]);
});


### What Happens

Normal Traffic (10 EC2 instances):
10 EC2 × 20 connections = 200 connections to RDS
RDS max: 367 connections
Usage: 200/367 = 54% ✓ OK


Black Friday Spike (50 EC2 instances auto-scaled):
50 EC2 × 20 connections = 1,000 connections needed
RDS max: 367 connections
Usage: 1,000/367 = 272% ✗ PROBLEM!


### Problems

1. Connection Exhaustion:
javascript
// Error on new EC2 instances
Error: remaining connection slots are reserved for non-replication superuser connections


2. Slow Connection Establishment:
Each new EC2 instance:
- Creates 20 new connections
- Takes 2-5 seconds to establish
- Delays first requests


3. Failover Issues:
RDS failover occurs (60-120 seconds):
- All 200 connections break
- All 10 EC2 instances try to reconnect simultaneously
- 200 × reconnection attempts = Database overwhelmed
- Application downtime: 2-5 minutes


4. Idle Connection Waste:
Off-peak hours (2 AM):
- Only 2 EC2 instances active
- Still holding 2 × 20 = 40 connections
- 38 connections idle, wasting resources


### Monitoring Results

bash
# Connection errors during spike
DatabaseConnections: 367 (maxed out)
ConnectionErrors: 633 (1000 - 367)
Application errors: 63% of requests fail


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## With RDS Proxy

### Architecture
50 EC2 instances → RDS Proxy (connection pooling) → RDS PostgreSQL


### Application Code
javascript
const { Pool } = require('pg');

// Connect to RDS Proxy instead
const pool = new Pool({
  host: 'my-rds-proxy.proxy-xxxxx.us-east-1.rds.amazonaws.com',
  port: 5432,
  database: 'products_db',
  user: 'postgres',
  password: 'password',
  max: 20  // Same pool size
});

app.get('/products/:id', async (req, res) => {
  const result = await pool.query('SELECT * FROM products WHERE id = $1', [req.params.id]);
  res.json(result.rows[0]);
});


### RDS Proxy Configuration
bash
aws rds modify-db-proxy \
  --db-proxy-name my-rds-proxy \
  --max-connections-percent 80 \
  --max-idle-connections-percent 50


### What Happens

Normal Traffic (10 EC2 instances):
10 EC2 → Proxy: 200 connections (accepted)
Proxy → RDS: ~50 actual connections (pooled)
RDS usage: 50/367 = 14% ✓ Efficient


Black Friday Spike (50 EC2 instances):
50 EC2 → Proxy: 1,000 connections (accepted)
Proxy → RDS: ~250 actual connections (pooled)
RDS usage: 250/367 = 68% ✓ No errors!


### Benefits

1. Connection Multiplexing:
Application sees: 1,000 connections
RDS sees: 250 connections
Proxy reuses connections efficiently


2. Fast Scaling:
New EC2 instance starts:
- Connects to proxy instantly (<100ms)
- No need to establish RDS connections
- Immediate request handling


3. Automatic Failover:
RDS failover occurs:
- Proxy maintains connections to EC2
- Proxy reconnects to new RDS primary
- Application sees brief latency increase (5-10s)
- No connection errors to application
- Downtime: 10-30 seconds (vs 2-5 minutes)


4. Idle Connection Management:
Off-peak hours (2 AM):
- 2 EC2 instances active
- Proxy → RDS: Only 10 connections (not 40)
- Proxy closes idle connections automatically


### Monitoring Results

bash
# No connection errors during spike
ClientConnections: 1,000 (to proxy)
DatabaseConnections: 250 (to RDS)
ConnectionErrors: 0
Application errors: 0%


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Side-by-Side Comparison

### Scenario 1: Normal Operation

Without Proxy:
10 EC2 instances
200 connections to RDS
Connection overhead: High
RDS CPU: 15%


With Proxy:
10 EC2 instances
200 connections to proxy
50 connections to RDS
Connection overhead: Low
RDS CPU: 8%


### Scenario 2: Traffic Spike (Auto-scaling)

Without Proxy:
50 EC2 instances scale up
1,000 connections needed
367 connections available
633 requests fail
Error rate: 63%
Time to recover: 5-10 minutes


With Proxy:
50 EC2 instances scale up
1,000 connections to proxy
250 connections to RDS
0 requests fail
Error rate: 0%
Time to scale: Instant


### Scenario 3: RDS Failover

Without Proxy:
Primary fails
All 200 connections break
All EC2 instances reconnect
Reconnection storm
Downtime: 2-5 minutes


With Proxy:
Primary fails
Proxy maintains EC2 connections
Proxy reconnects to new primary
Transparent to application
Downtime: 10-30 seconds


### Scenario 4: Lambda Functions (Serverless)

Without Proxy:
100 Lambda invocations
Each creates new connection
100 connections to RDS
Connection time: 2-5 seconds each
Total overhead: 200-500 seconds


With Proxy:
100 Lambda invocations
Reuse proxy connections
Connection time: <100ms each
Total overhead: 10 seconds
95% faster!


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Real Numbers Example

### Cost Analysis (Monthly)

Without Proxy:
RDS db.m5.large (901 connections): $150/month
Need larger instance for connection overhead
Total: $150/month


With Proxy:
RDS db.t3.medium (367 connections): $60/month
RDS Proxy: $15/month (per proxy)
Total: $75/month
Savings: $75/month (50% cheaper)


### Performance Metrics

| Metric | Without Proxy | With Proxy |
|--------|---------------|------------|
| Connection time | 2-5 seconds | <100ms |
| Failover time | 2-5 minutes | 10-30 seconds |
| Max concurrent users | 367 | Unlimited* |
| Connection errors | High during spikes | None |
| RDS CPU usage | 15-20% | 8-12% |
| Scaling time | 5-10 minutes | Instant |

Limited by RDS instance capacity, not connections

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Code Comparison

### Handling Failover

Without Proxy:
javascript
const pool = new Pool({ host: 'rds-endpoint' });

// Need complex retry logic
async function queryWithRetry(sql, params) {
  let retries = 5;
  while (retries > 0) {
    try {
      return await pool.query(sql, params);
    } catch (error) {
      if (error.code === 'ECONNREFUSED') {
        retries--;
        await new Promise(r => setTimeout(r, 5000));
        // Recreate pool
        await pool.end();
        pool = new Pool({ host: 'rds-endpoint' });
      } else {
        throw error;
      }
    }
  }
}


With Proxy:
javascript
const pool = new Pool({ host: 'proxy-endpoint' });

// Simple query, proxy handles failover
async function query(sql, params) {
  return await pool.query(sql, params);
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

### Use RDS Proxy When:
- ✅ Auto-scaling EC2 instances
- ✅ Using Lambda functions
- ✅ Traffic spikes expected
- ✅ Need high availability
- ✅ Many application instances
- ✅ Connection pooling needed

### Skip RDS Proxy When:
- ❌ Single EC2 instance
- ❌ Predictable, low traffic
- ❌ No auto-scaling
- ❌ Cost-sensitive (small apps)

Bottom line: RDS Proxy prevents connection exhaustion, enables instant scaling, and reduces failover time 
from minutes to seconds.
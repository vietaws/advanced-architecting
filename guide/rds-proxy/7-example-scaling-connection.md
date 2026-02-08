## RDS Proxy Connection Management to RDS PostgreSQL

### Your Setup
Application → 20 connections → RDS Proxy → ? connections → RDS PostgreSQL


### RDS Proxy Configuration

bash
# View current settings
aws rds describe-db-proxies \
  --db-proxy-name my-rds-proxy

# Key parameters that control Proxy → RDS connections
MaxConnectionsPercent: 80%           # Max % of RDS connections proxy can use
MaxIdleConnectionsPercent: 50%       # % kept idle in pool
ConnectionBorrowTimeout: 120         # Seconds to wait for connection


### Calculate Proxy → RDS Connections

Example: RDS db.t3.medium (367 max connections)

MaxConnectionsPercent: 80%
Max proxy connections = 367 × 0.80 = 293 connections

MaxIdleConnectionsPercent: 50%
Idle connections = 293 × 0.50 = 146 connections
Active connections = 293 - 146 = 147 connections


## Scenario 1: Normal Peak (Steady Load)

### Setup
- **Application**: 10 EC2 instances
- **App pool**: 20 connections per EC2 = 200 total to proxy
- **Traffic**: 100 requests/second
- **Query time**: 10ms average

### Connection Flow

Initial State (Application Startup):
Time: 0s
App → Proxy: 0 connections
Proxy → RDS: 0 connections

Application starts:
App → Proxy: 200 connections established (instant)
Proxy → RDS: 0 connections (lazy initialization)


First Requests Arrive:
Time: 1s
100 requests/second arrive

Proxy behavior:
├── Receives 100 requests
├── Opens 10 connections to RDS (based on concurrency)
├── Executes queries
└── Keeps connections open

App → Proxy: 200 connections
Proxy → RDS: 10 connections (actively used)


Steady State (After 1 minute):
Traffic: 100 req/s consistently
Query time: 10ms
Concurrent queries: 100 × 0.01 = 1 query at a time

Proxy → RDS: 5-10 connections maintained
├── 2-3 connections actively executing queries
├── 3-5 connections idle (ready for use)
└── 2-2 connections in "warm" state


### Connection Lifecycle

Minute 0-1: Ramp up
├── Proxy opens connections as needed
├── Reaches 10 connections
└── Stabilizes

Minute 1-60: Steady state
├── Maintains 10 connections
├── Reuses connections efficiently
├── No new connections opened
└── No connections closed

Hour 1+: Optimization
├── Proxy may close some idle connections
├── Keeps minimum based on traffic pattern
└── Settles at ~5-7 connections


## Scenario 2: Spiky Peak (Sudden Traffic Spike)

### Setup
- **Normal**: 100 req/s
- **Spike**: 1000 req/s (10x increase)
- **Duration**: 5 minutes
- **Query time**: 10ms

### Timeline: Spike Occurs

T = 0s (Before Spike):
Traffic: 100 req/s
App → Proxy: 200 connections
Proxy → RDS: 10 connections
RDS CPU: 15%


T = 1s (Spike Starts):
Traffic: 1000 req/s (sudden increase)

Proxy detects:
├── Request queue building up
├── All 10 RDS connections busy
└── Need more connections

Proxy action:
├── Opens 20 more connections to RDS (fast)
├── Total: 30 connections
└── Processes queued requests

App → Proxy: 200 connections (unchanged)
Proxy → RDS: 30 connections (increased)
Request latency: 50ms (includes 40ms queue wait)


T = 5s (Spike Continues):
Traffic: 1000 req/s sustained

Proxy behavior:
├── Monitors connection utilization
├── All 30 connections busy
├── Opens 20 more connections
└── Total: 50 connections

App → Proxy: 200 connections
Proxy → RDS: 50 connections
Request latency: 15ms (queue reduced)
RDS CPU: 45%


T = 30s (Spike Peak):
Traffic: 1000 req/s
Concurrent queries: 1000 × 0.01 = 10 concurrent

Proxy stabilizes:
├── 50 connections sufficient
├── No more connections needed
└── Efficient processing

App → Proxy: 200 connections
Proxy → RDS: 50 connections (stable)
Request latency: 12ms (normal)
RDS CPU: 50%


T = 5min (Spike Ends):
Traffic: Drops back to 100 req/s

Proxy behavior:
├── Detects reduced load
├── Keeps connections open (for now)
└── Marks excess as idle

App → Proxy: 200 connections
Proxy → RDS: 50 connections (40 idle, 10 active)


T = 10min (After Spike):
Traffic: 100 req/s (normal)

Proxy cleanup:
├── Closes idle connections gradually
├── Keeps minimum for current load
└── Returns to baseline

App → Proxy: 200 connections
Proxy → RDS: 10 connections (back to normal)
RDS CPU: 15%


## Scenario 3: Extreme Spike (Auto-Scaling)

### Setup
- **Normal**: 10 EC2 instances (200 connections to proxy)
- **Spike**: Auto-scales to 50 EC2 instances (1000 connections to proxy)
- **Traffic**: 5000 req/s
- **Query time**: 10ms

### Timeline

T = 0s (Before Spike):
EC2: 10 instances
App → Proxy: 200 connections
Proxy → RDS: 10 connections


T = 30s (Auto-Scaling Triggered):
EC2: 20 instances (scaling up)
App → Proxy: 400 connections (new EC2s connect)
Traffic: 2000 req/s

Proxy response:
├── Accepts 200 new connections instantly
├── Opens 40 more RDS connections
└── Total: 50 RDS connections

App → Proxy: 400 connections
Proxy → RDS: 50 connections


T = 2min (Full Scale):
EC2: 50 instances (fully scaled)
App → Proxy: 1000 connections
Traffic: 5000 req/s
Concurrent queries: 5000 × 0.01 = 50 concurrent

Proxy response:
├── Accepts all 1000 app connections
├── Opens 100 RDS connections
└── Processes efficiently

App → Proxy: 1000 connections
Proxy → RDS: 100 connections
Request latency: 15ms
RDS CPU: 70%


T = 10min (Scale Down Begins):
Traffic drops: 1000 req/s
EC2: Scales down to 20 instances
App → Proxy: 400 connections (600 closed by terminated EC2s)

Proxy response:
├── Detects 600 app connections closed
├── Reduces RDS connections gradually
└── Keeps 30 connections for current load

App → Proxy: 400 connections
Proxy → RDS: 30 connections


## Scenario 4: Slow Queries (Long-Running)

### Setup
- **Traffic**: 100 req/s
- **Query time**: 500ms (slow!)
- **Concurrent queries**: 100 × 0.5 = 50 concurrent

### Connection Behavior

T = 0s (Slow Queries Start):
First 100 requests arrive

Proxy behavior:
├── Opens 10 connections
├── All busy (500ms each)
├── Requests queue up
└── Opens more connections

App → Proxy: 200 connections
Proxy → RDS: 10 connections (all busy)
Queue: 90 requests waiting


T = 1s:
Proxy detects:
├── All connections busy for >100ms
├── Queue building up
└── Opens 40 more connections

App → Proxy: 200 connections
Proxy → RDS: 50 connections (all busy)
Queue: 50 requests waiting


T = 5s (Stabilized):
Proxy opens enough connections for concurrency

App → Proxy: 200 connections
Proxy → RDS: 60 connections (handling 50 concurrent queries)
Queue: 0 requests
Request latency: 500ms (query time only)


## Scenario 5: Connection Limit Reached

### Setup
- **RDS**: db.t3.medium (367 max connections)
- **MaxConnectionsPercent**: 80% (293 max for proxy)
- **Traffic**: Extreme spike

### What Happens

Proxy reaches limit:
App → Proxy: 2000 connections
Proxy → RDS: 293 connections (MAX reached)
Traffic: 10,000 req/s

Proxy behavior:
├── Cannot open more RDS connections
├── Queues requests
├── Uses ConnectionBorrowTimeout (120s)
└── Returns errors if timeout exceeded

Request outcomes:
├── Fast queries (<120s): Success (queued)
├── Slow queries (>120s): Error "connection timeout"
└── Average wait time: 50-100ms


Error example:
javascript
// Application receives error
Error: timeout acquiring connection from pool
Code: ETIMEDOUT

// Solution: Upgrade RDS instance
aws rds modify-db-instance \
  --db-instance-identifier my-db \
  --db-instance-class db.m5.large \  # 901 max connections
  --apply-immediately


## Connection Management Algorithm

### Proxy Decision Logic

Every 1 second, Proxy evaluates:

1. Check current utilization:
   Active connections / Total connections = Utilization %

2. If Utilization > 80%:
   ├── Open more connections (up to MaxConnectionsPercent)
   └── Increment by 20% of current

3. If Utilization < 30% for 5 minutes:
   ├── Close idle connections
   └── Keep minimum based on recent peak

4. If at MaxConnectionsPercent:
   ├── Queue new requests
   └── Wait for available connection (ConnectionBorrowTimeout)

5. If ConnectionBorrowTimeout exceeded:
   └── Return error to application


## Monitoring Connection Behavior

### CloudWatch Metrics

bash
# Monitor proxy → RDS connections
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBProxyName,Value=my-rds-proxy \
  --start-time 2026-02-08T17:00:00Z \
  --end-time 2026-02-08T18:00:00Z \
  --period 60 \
  --statistics Average,Maximum

# Monitor app → proxy connections
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ClientConnections \
  --dimensions Name=DBProxyName,Value=my-rds-proxy \
  --start-time 2026-02-08T17:00:00Z \
  --end-time 2026-02-08T18:00:00Z \
  --period 60 \
  --statistics Average,Maximum

# Monitor query latency
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name QueryDatabaseResponseLatency \
  --dimensions Name=DBProxyName,Value=my-rds-proxy \
  --start-time 2026-02-08T17:00:00Z \
  --end-time 2026-02-08T18:00:00Z \
  --period 60 \
  --statistics Average,p99


## Summary Table

| Scenario | App→Proxy | Proxy→RDS | Behavior |
|----------|-----------|-----------|----------|
| Startup | 200 | 0 → 10 | Lazy initialization |
| Normal peak | 200 | 10 | Stable, efficient |
| Spiky peak | 200 | 10 → 50 → 10 | Auto-scales up/down |
| Auto-scale | 200 → 1000 | 10 → 100 | Scales with load |
| Slow queries | 200 | 10 → 60 | Opens more for concurrency |
| At limit | 2000 | 293 (max) | Queues requests |

### Key Takeaways

1. Proxy → RDS connections are dynamic - Opens/closes based on load
2. App → Proxy connections are static - Your pool size (20 per EC2)
3. Proxy is intelligent - Scales connections automatically
4. No manual management needed - Proxy handles everything
5. Monitor metrics - Watch for hitting MaxConnectionsPercent

The proxy automatically manages connections to RDS based on actual concurrent query load, not the number 
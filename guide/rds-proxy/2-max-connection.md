## RDS Proxy Connection Limits & Best Practices

### Maximum Connections

RDS Proxy Limits:
- **Max connections TO proxy**: Unlimited (from applications)
- **Max connections FROM proxy to RDS**: Depends on RDS instance class

RDS Instance Connection Limits:

| Instance Class | Max Connections |
|----------------|-----------------|
| db.t3.micro | 87 |
| db.t3.small | 177 |
| db.t3.medium | 367 |
| db.t4g.micro | 87 |
| db.t4g.small | 177 |
| db.m5.large | 901 |
| db.m5.xlarge | 1,802 |
| db.m5.2xlarge | 3,604 |
| db.r5.large | 1,600 |
| db.r5.xlarge | 3,200 |

Formula for PostgreSQL:
max_connections = (DBInstanceClassMemory / 9531392) - 1


### RDS Proxy Configuration

Default Settings:

bash
# View proxy settings
aws rds describe-db-proxies \
  --db-proxy-name my-rds-proxy \
  --query 'DBProxies[0].[MaxConnectionsPercent,MaxIdleConnectionsPercent,ConnectionBorrowTimeout]'


Key Parameters:

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| MaxConnectionsPercent | 100% | 1-100% | % of RDS max connections proxy can use |
| MaxIdleConnectionsPercent | 50% | 0-100% | % of connections kept idle in pool |
| ConnectionBorrowTimeout | 120 sec | 0-3600 sec | Timeout waiting for connection |

### Configure Connection Limits

bash
# Modify proxy settings
aws rds modify-db-proxy \
  --db-proxy-name my-rds-proxy \
  --max-connections-percent 75 \
  --max-idle-connections-percent 50 \
  --connection-borrow-timeout 120


Example Calculation:

RDS Instance: db.m5.large (901 max connections)
MaxConnectionsPercent: 75%

Proxy max connections = 901 × 0.75 = 675 connections
Idle connections = 675 × 0.50 = 337 connections
Active connections = 675 - 337 = 338 connections


### Connection Pooling Strategy

Scenario: 10 EC2 instances, each with 20 connection pool

Without RDS Proxy:
10 EC2 × 20 connections = 200 connections to RDS
Problem: Wastes connections, hits limits quickly


With RDS Proxy:
10 EC2 × 20 connections = 200 connections to Proxy
Proxy → RDS = ~50-100 actual connections (pooled)
Benefit: Efficient connection reuse


### Connection Timeouts & TTL

Connection Borrow Timeout:
bash
# How long to wait for available connection
--connection-borrow-timeout 120  # 120 seconds (default)


Idle Connection Timeout:
- RDS Proxy automatically closes idle connections
- No explicit TTL setting
- Managed by MaxIdleConnectionsPercent

Application Connection Timeout:
javascript
const pool = new Pool({
  host: 'proxy-endpoint',
  connectionTimeoutMillis: 2000,  // 2 seconds to establish connection
  idleTimeoutMillis: 30000,       // 30 seconds idle before closing
  max: 20
});


### Service Quotas

AWS Account Limits:

| Quota | Default | Adjustable |
|-------|---------|------------|
| Proxies per region | 20 | Yes (up to 60) |
| Proxies per RDS instance | 20 | Yes |
| Target groups per proxy | 1 | No |
| Endpoints per proxy | 20 | Yes |

Check quotas:
bash
aws service-quotas list-service-quotas \
  --service-code rds \
  --query 'Quotas[?contains(QuotaName, `Proxy`)]'


Request increase:
bash
aws service-quotas request-service-quota-increase \
  --service-code rds \
  --quota-code L-D94C7EA3 \
  --desired-value 40


### Best Practices

#### 1. Size Application Connection Pool

Rule of thumb:
Application pool size = (Number of concurrent requests / Average query time) + Buffer

Example:
- 100 concurrent requests
- 50ms average query time
- Pool size = (100 / 0.05) + 10 = 30 connections


Code:
javascript
const pool = new Pool({
  host: process.env.DB_PROXY_ENDPOINT,
  max: 20,  // Keep small, proxy handles pooling
  min: 2,   // Minimum connections
  idleTimeoutMillis: 30000
});


#### 2. Configure MaxConnectionsPercent

Conservative (Recommended):
bash
# Leave 25% headroom for admin connections
--max-connections-percent 75


Aggressive (High traffic):
bash
# Use more connections
--max-connections-percent 90


#### 3. Set Appropriate Timeouts

bash
# Fast-fail for overload scenarios
--connection-borrow-timeout 30  # 30 seconds

# Longer timeout for batch jobs
--connection-borrow-timeout 300  # 5 minutes


#### 4. Monitor Connection Usage

bash
# Monitor proxy connections
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBProxyName,Value=my-rds-proxy \
  --start-time 2026-02-08T00:00:00Z \
  --end-time 2026-02-08T17:00:00Z \
  --period 300 \
  --statistics Maximum,Average

# Monitor client connections
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ClientConnections \
  --dimensions Name=DBProxyName,Value=my-rds-proxy \
  --start-time 2026-02-08T00:00:00Z \
  --end-time 2026-02-08T17:00:00Z \
  --period 300 \
  --statistics Maximum,Average


#### 5. Handle Connection Errors

javascript
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_PROXY_ENDPOINT,
  max: 20,
  connectionTimeoutMillis: 2000,
  idleTimeoutMillis: 30000
});

async function queryWithRetry(sql, params, maxRetries = 3) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      const result = await pool.query(sql, params);
      return result.rows;
    } catch (error) {
      // Connection timeout or pool exhausted
      if (error.code === 'ETIMEDOUT' || error.message.includes('timeout')) {
        console.warn(`Query timeout, retry ${i + 1}/${maxRetries}`);
        await new Promise(resolve => setTimeout(resolve, 1000 * (i + 1)));
        continue;
      }
      throw error;
    }
  }
  throw new Error('Max retries exceeded');
}


### Connection Lifecycle

1. Application → Proxy:
App creates connection → Proxy accepts (unlimited)


2. Proxy → RDS:
Proxy borrows from pool → If available: immediate
                        → If not: waits (ConnectionBorrowTimeout)
                        → If timeout: returns error to app


3. Connection Reuse:
App finishes query → Connection returned to proxy pool
                   → Proxy keeps idle (MaxIdleConnectionsPercent)
                   → Reused for next request


4. Connection Cleanup:
Idle > threshold → Proxy closes connection to RDS
                 → Frees up resources


### Sizing Recommendations

Small Application (< 10 EC2 instances):
bash
RDS: db.t3.medium (367 connections)
Proxy MaxConnectionsPercent: 75% (275 connections)
App pool size: 10-20 per instance


Medium Application (10-50 EC2 instances):
bash
RDS: db.m5.large (901 connections)
Proxy MaxConnectionsPercent: 80% (720 connections)
App pool size: 10-15 per instance


Large Application (50+ EC2 instances):
bash
RDS: db.m5.xlarge (1,802 connections)
Proxy MaxConnectionsPercent: 85% (1,531 connections)
App pool size: 10-20 per instance


### Common Issues & Solutions

Issue 1: Connection Timeout
Error: timeout acquiring connection from pool


Solution:
bash
# Increase timeout or connections
aws rds modify-db-proxy \
  --db-proxy-name my-rds-proxy \
  --connection-borrow-timeout 180 \
  --max-connections-percent 85


Issue 2: Too Many Connections
Error: remaining connection slots are reserved


Solution:
bash
# Reduce app pool size or upgrade RDS instance
# db.t3.medium → db.m5.large
aws rds modify-db-instance \
  --db-instance-identifier my-db \
  --db-instance-class db.m5.large \
  --apply-immediately


Issue 3: Connection Leaks
javascript
// Always release connections
const client = await pool.connect();
try {
  await client.query(sql);
} finally {
  client.release();  // Critical!
}


### Monitoring Checklist

bash
# 1. Client connections (from apps to proxy)
ClientConnections

# 2. Database connections (from proxy to RDS)
DatabaseConnections

# 3. Connection borrow timeouts
QueryDatabaseResponseLatency

# 4. Failed connections
ClientConnectionsClosed


### Summary

| Metric | Recommended Value |
|--------|-------------------|
| App pool size | 10-20 per instance |
| MaxConnectionsPercent | 75-85% |
| MaxIdleConnectionsPercent | 50% |
| ConnectionBorrowTimeout | 30-120 seconds |
| Monitor threshold | > 80% of max connections |
| Scale up trigger | Consistent > 70% usage |

Keep application pools small (10-20), let RDS Proxy handle the pooling efficiently.
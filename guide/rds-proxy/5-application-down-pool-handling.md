## What Happens When EC2 Application Goes Down

### Automatic Cleanup by RDS Proxy

RDS Proxy automatically handles cleanup - you don't need to do anything manually.

### Scenario: EC2 Instance Crashes

Before crash:
EC2 Instance → 20 connections → RDS Proxy → 5 connections → RDS

EC2 crashes:
EC2 Instance (down) ✗ → 20 broken connections → RDS Proxy

RDS Proxy detects:
- TCP connections broken
- No heartbeat from EC2
- Closes connections automatically (within seconds)

After cleanup:
RDS Proxy → 0 connections → RDS (connections released)


### How RDS Proxy Detects Dead Connections

1. TCP Keepalive:
RDS Proxy sends TCP keepalive packets
If no response → Connection marked as dead
Cleanup time: 5-10 seconds


2. Idle Timeout:
No activity on connection
After idle timeout → Connection closed
Default: Based on MaxIdleConnectionsPercent


3. Client Disconnect:
EC2 sends FIN packet (graceful shutdown)
RDS Proxy immediately closes connection
Cleanup time: Instant


## Different Shutdown Scenarios

### Scenario 1: Graceful Shutdown (Best Case)

Application code:
javascript
const { Pool } = require('pg');

const pool = new Pool({
  host: 'proxy-endpoint',
  max: 20
});

// Graceful shutdown handler
process.on('SIGTERM', async () => {
  console.log('Shutting down gracefully...');
  
  // Close all connections in pool
  await pool.end();
  
  console.log('All connections closed');
  process.exit(0);
});

process.on('SIGINT', async () => {
  await pool.end();
  process.exit(0);
});


What happens:
1. EC2 receives shutdown signal
2. Application calls pool.end()
3. Pool closes all 20 connections gracefully
4. RDS Proxy receives FIN packets
5. RDS Proxy releases connections to RDS
6. Cleanup time: <1 second


### Scenario 2: Sudden Crash (EC2 Terminated)

No cleanup code runs:
javascript
// Application crashes or EC2 terminated
// No pool.end() called


What happens:
1. EC2 instance terminates
2. TCP connections break
3. RDS Proxy detects broken connections (5-10 seconds)
4. RDS Proxy closes connections automatically
5. Connections returned to pool
6. Cleanup time: 5-10 seconds


No action needed - RDS Proxy handles it automatically

### Scenario 3: Network Partition

EC2 loses network connectivity:
EC2 (alive but no network) → ✗ → RDS Proxy


What happens:
1. Network connection lost
2. RDS Proxy TCP keepalive fails
3. RDS Proxy marks connections as dead
4. Connections cleaned up after timeout
5. Cleanup time: 10-30 seconds


## Monitoring Connection Cleanup

### Check Active Connections

bash
# Monitor client connections to proxy
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ClientConnections \
  --dimensions Name=DBProxyName,Value=my-rds-proxy \
  --start-time 2026-02-08T17:00:00Z \
  --end-time 2026-02-08T18:00:00Z \
  --period 60 \
  --statistics Average,Maximum

# Monitor database connections from proxy to RDS
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBProxyName,Value=my-rds-proxy \
  --start-time 2026-02-08T17:00:00Z \
  --end-time 2026-02-08T18:00:00Z \
  --period 60 \
  --statistics Average,Maximum


### Example Metrics During EC2 Shutdown

Time    ClientConnections  DatabaseConnections
17:00   200               50
17:01   200               50
17:02   180 (EC2 down)    48
17:03   160               45
17:04   140               42
17:05   120               38
17:06   100               35


## Best Practices for Connection Management

### 1. Implement Graceful Shutdown

javascript
const express = require('express');
const { Pool } = require('pg');

const app = express();
const pool = new Pool({ host: 'proxy-endpoint', max: 20 });

let server;

// Start server
server = app.listen(3000, () => {
  console.log('Server started');
});

// Graceful shutdown
async function shutdown(signal) {
  console.log(`${signal} received, shutting down gracefully`);
  
  // Stop accepting new requests
  server.close(() => {
    console.log('HTTP server closed');
  });
  
  // Close database connections
  await pool.end();
  console.log('Database connections closed');
  
  process.exit(0);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));


### 2. Use Health Checks

javascript
// Health check endpoint
app.get('/health', async (req, res) => {
  try {
    // Test database connection
    await pool.query('SELECT 1');
    res.status(200).json({ status: 'healthy' });
  } catch (error) {
    res.status(503).json({ status: 'unhealthy', error: error.message });
  }
});


Load balancer configuration:
bash
# ALB health check
aws elbv2 modify-target-group \
  --target-group-arn arn:aws:elasticloadbalancing:... \
  --health-check-path /health \
  --health-check-interval-seconds 30 \
  --unhealthy-threshold-count 2


### 3. Handle Connection Errors

javascript
const pool = new Pool({
  host: 'proxy-endpoint',
  max: 20,
  connectionTimeoutMillis: 2000
});

// Handle pool errors
pool.on('error', (err, client) => {
  console.error('Unexpected pool error:', err);
  // Don't exit process, pool will recover
});

// Query with error handling
async function queryWithRetry(sql, params, retries = 3) {
  for (let i = 0; i < retries; i++) {
    try {
      return await pool.query(sql, params);
    } catch (error) {
      if (i === retries - 1) throw error;
      console.warn(`Query failed, retry ${i + 1}/${retries}`);
      await new Promise(r => setTimeout(r, 1000));
    }
  }
}


### 4. Set Appropriate Timeouts

javascript
const pool = new Pool({
  host: 'proxy-endpoint',
  max: 20,
  
  // Connection timeouts
  connectionTimeoutMillis: 2000,  // Fail fast if no connection
  idleTimeoutMillis: 30000,       // Close idle connections
  
  // Query timeout
  statement_timeout: 30000        // 30 second query timeout
});


## Auto Scaling Group Considerations

### When ASG Terminates EC2 Instances

bash
# ASG lifecycle hook for graceful shutdown
aws autoscaling put-lifecycle-hook \
  --lifecycle-hook-name graceful-shutdown \
  --auto-scaling-group-name my-asg \
  --lifecycle-transition autoscaling:EC2_INSTANCE_TERMINATING \
  --default-result CONTINUE \
  --heartbeat-timeout 60


Application handles lifecycle hook:
javascript
const AWS = require('aws-sdk');
const autoscaling = new AWS.AutoScaling();

// Listen for termination signal
process.on('SIGTERM', async () => {
  console.log('Instance terminating, cleaning up...');
  
  // Close connections
  await pool.end();
  
  // Complete lifecycle action
  await autoscaling.completeLifecycleAction({
    LifecycleHookName: 'graceful-shutdown',
    AutoScalingGroupName: 'my-asg',
    LifecycleActionResult: 'CONTINUE',
    InstanceId: process.env.INSTANCE_ID
  }).promise();
  
  process.exit(0);
});


## Connection Leak Prevention

### Monitor for Leaks

javascript
// Log pool stats periodically
setInterval(() => {
  console.log('Pool stats:', {
    total: pool.totalCount,
    idle: pool.idleCount,
    waiting: pool.waitingCount
  });
  
  // Alert if too many waiting
  if (pool.waitingCount > 10) {
    console.error('Connection pool exhausted!');
  }
}, 60000);


### Always Release Connections

javascript
// ✅ GOOD - Always release
app.get('/products/:id', async (req, res) => {
  const client = await pool.connect();
  try {
    const result = await client.query('SELECT * FROM products WHERE id = $1', [req.params.id]);
    res.json(result.rows[0]);
  } finally {
    client.release();  // Always runs
  }
});

// ✅ BETTER - Use pool.query (auto-release)
app.get('/products/:id', async (req, res) => {
  const result = await pool.query('SELECT * FROM products WHERE id = $1', [req.params.id]);
  res.json(result.rows[0]);
});


## Summary

### RDS Proxy Automatic Cleanup

| Scenario | Cleanup Time | Action Required |
|----------|--------------|-----------------|
| Graceful shutdown | <1 second | Implement pool.end() |
| EC2 crash | 5-10 seconds | None (automatic) |
| EC2 terminated | 5-10 seconds | None (automatic) |
| Network partition | 10-30 seconds | None (automatic) |
| Connection leak | Based on idle timeout | Fix application code |

### Key Points

1. RDS Proxy handles cleanup automatically - No manual intervention needed
2. Implement graceful shutdown - Faster cleanup, better user experience
3. Use health checks - Detect unhealthy instances early
4. Monitor connection metrics - Detect leaks and issues
5. Always release connections - Prevent connection leaks

You don't need to manage RDS Proxy connections manually - it's fully automatic.
No, you should NOT open and close connections for every database call.

## Wrong Approach (Don't Do This)

javascript
// ❌ BAD - Opens and closes connection every time
app.get('/products/:id', async (req, res) => {
  // Create new connection
  const client = new Client({
    host: 'db-endpoint',
    user: 'postgres',
    password: 'password',
    database: 'products_db'
  });
  
  await client.connect();  // Slow! 2-5 seconds
  const result = await client.query('SELECT * FROM products WHERE id = $1', [req.params.id]);
  await client.end();      // Closes connection
  
  res.json(result.rows[0]);
});


Problems:
- Each request takes 2-5 seconds to connect
- Wastes resources creating/destroying connections
- Overwhelms database with connection requests
- Very slow performance

## Correct Approach (Use Connection Pool)

javascript
const { Pool } = require('pg');

// ✅ GOOD - Create pool once at startup
const pool = new Pool({
  host: 'db-endpoint',
  user: 'postgres',
  password: 'password',
  database: 'products_db',
  max: 20,  // Keep 20 connections ready
  min: 2    // Always keep 2 connections open
});

// Reuse connections from pool
app.get('/products/:id', async (req, res) => {
  // Borrows connection from pool (instant, <1ms)
  const result = await pool.query('SELECT * FROM products WHERE id = $1', [req.params.id]);
  // Connection automatically returned to pool
  
  res.json(result.rows[0]);
});


## How Connection Pool Works

### Pool Lifecycle

Application Startup:
├── Create pool with 20 max connections
├── Open 2 initial connections (min)
└── Keep connections alive

Request 1:
├── Borrow connection from pool (instant)
├── Execute query
└── Return connection to pool (still open)

Request 2:
├── Reuse same connection (instant)
├── Execute query
└── Return connection to pool

Request 21 (pool exhausted):
├── Wait for available connection
├── Timeout if none available
└── Or queue the request


### Visual Example

Pool (max: 20 connections):
┌─────────────────────────────────┐
│ [Conn1] [Conn2] [Conn3] ... [Conn20] │
└─────────────────────────────────┘
      ↓        ↓        ↓
   Request1 Request2 Request3
      ↓        ↓        ↓
   (query)  (query)  (query)
      ↓        ↓        ↓
   Return   Return   Return
      ↓        ↓        ↓
   [Conn1] [Conn2] [Conn3]  ← Back to pool


## Different Query Methods

### Method 1: Simple Query (Recommended)

javascript
// Pool automatically manages connection
app.get('/products/:id', async (req, res) => {
  const result = await pool.query(
    'SELECT * FROM products WHERE id = $1',
    [req.params.id]
  );
  res.json(result.rows[0]);
});


What happens:
1. Pool borrows connection
2. Executes query
3. Returns connection automatically

### Method 2: Manual Connection Management

javascript
// Use when you need multiple queries in sequence
app.post('/orders', async (req, res) => {
  const client = await pool.connect();  // Borrow from pool
  
  try {
    await client.query('BEGIN');
    
    const order = await client.query(
      'INSERT INTO orders (user_id, total) VALUES ($1, $2) RETURNING id',
      [req.body.userId, req.body.total]
    );
    
    await client.query(
      'INSERT INTO order_items (order_id, product_id) VALUES ($1, $2)',
      [order.rows[0].id, req.body.productId]
    );
    
    await client.query('COMMIT');
    res.json(order.rows[0]);
    
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();  // MUST return to pool
  }
});


Important: Always use finally to release connection

### Method 3: Transaction Helper

javascript
// Cleaner transaction handling
async function withTransaction(callback) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

// Usage
app.post('/orders', async (req, res) => {
  const order = await withTransaction(async (client) => {
    const orderResult = await client.query(
      'INSERT INTO orders (user_id, total) VALUES ($1, $2) RETURNING id',
      [req.body.userId, req.body.total]
    );
    
    await client.query(
      'INSERT INTO order_items (order_id, product_id) VALUES ($1, $2)',
      [orderResult.rows[0].id, req.body.productId]
    );
    
    return orderResult.rows[0];
  });
  
  res.json(order);
});


## Connection Pool Configuration

javascript
const pool = new Pool({
  host: 'db-endpoint',
  user: 'postgres',
  password: 'password',
  database: 'products_db',
  
  // Pool settings
  max: 20,                      // Maximum connections in pool
  min: 2,                       // Minimum connections always open
  idleTimeoutMillis: 30000,     // Close idle connections after 30s
  connectionTimeoutMillis: 2000, // Timeout if no connection available
  
  // Keep connections alive
  keepAlive: true,
  keepAliveInitialDelayMillis: 10000
});


## Performance Comparison

### Opening/Closing Every Time

javascript
// ❌ BAD
async function getProduct(id) {
  const client = new Client({ host: 'db-endpoint' });
  await client.connect();  // 2000ms
  const result = await client.query('SELECT * FROM products WHERE id = $1', [id]);  // 10ms
  await client.end();      // 100ms
  return result.rows[0];
}

// Total time: 2110ms per request
// 1000 requests = 2,110 seconds (35 minutes!)


### Using Connection Pool

javascript
// ✅ GOOD
async function getProduct(id) {
  const result = await pool.query('SELECT * FROM products WHERE id = $1', [id]);  // 10ms
  return result.rows[0];
}

// Total time: 10ms per request
// 1000 requests = 10 seconds
// 211x faster!


## Common Mistakes

### Mistake 1: Not Releasing Connection

javascript
// ❌ Connection leak
app.get('/products/:id', async (req, res) => {
  const client = await pool.connect();
  const result = await client.query('SELECT * FROM products WHERE id = $1', [req.params.id]);
  // Forgot client.release()!
  res.json(result.rows[0]);
});

// After 20 requests, pool is exhausted
// Request 21 hangs forever


### Mistake 2: Closing Pool Prematurely

javascript
// ❌ Don't close pool after each request
app.get('/products/:id', async (req, res) => {
  const result = await pool.query('SELECT * FROM products WHERE id = $1', [req.params.id]);
  await pool.end();  // Wrong! Closes entire pool
  res.json(result.rows[0]);
});


### Mistake 3: Creating Multiple Pools

javascript
// ❌ Don't create pool per request
app.get('/products/:id', async (req, res) => {
  const pool = new Pool({ host: 'db-endpoint' });  // Wrong!
  const result = await pool.query('SELECT * FROM products WHERE id = $1', [req.params.id]);
  res.json(result.rows[0]);
});


## Correct Application Structure

javascript
const express = require('express');
const { Pool } = require('pg');

const app = express();

// 1. Create pool ONCE at startup
const pool = new Pool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  max: 20
});

// 2. Use pool for all queries
app.get('/products/:id', async (req, res) => {
  const result = await pool.query('SELECT * FROM products WHERE id = $1', [req.params.id]);
  res.json(result.rows[0]);
});

app.post('/products', async (req, res) => {
  const result = await pool.query(
    'INSERT INTO products (name, price) VALUES ($1, $2) RETURNING *',
    [req.body.name, req.body.price]
  );
  res.json(result.rows[0]);
});

// 3. Close pool on shutdown
process.on('SIGTERM', async () => {
  await pool.end();
  process.exit(0);
});

app.listen(3000);


## Summary

| Approach | Connection Time | Best For |
|----------|----------------|----------|
| Open/Close per request | 2-5 seconds | Never use |
| Connection Pool | <1ms | Always use |
| Single connection | 0ms (reuse) | Single-threaded apps only |

Best practice: Create one connection pool at application startup, reuse connections for all queries, close
pool only on application shutdown.
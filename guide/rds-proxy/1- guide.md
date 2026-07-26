## Connect EC2 Application to RDS PostgreSQL via RDS Proxy

### Step 1: Create RDS Proxy

bash
# Create IAM role for RDS Proxy
aws iam create-role \
  --role-name rds-proxy-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "Service": "rds.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach Secrets Manager policy
aws iam attach-role-policy \
  --role-name rds-proxy-role \
  --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite

# Create secret for database credentials
aws secretsmanager create-secret \
  --name rds-db-credentials \
  --secret-string '{
    "username": "postgres",
    "password": "your-password"
  }'

# Create RDS Proxy
aws rds create-db-proxy \
  --db-proxy-name my-rds-proxy \
  --engine-family POSTGRESQL \
  --auth '{
    "AuthScheme": "SECRETS",
    "SecretArn": "arn:aws:secretsmanager:us-east-1:ACCOUNT-ID:secret:rds-db-credentials-xxxxx",
    "IAMAuth": "DISABLED"
  }' \
  --role-arn arn:aws:iam::ACCOUNT-ID:role/rds-proxy-role \
  --vpc-subnet-ids subnet-xxxxx subnet-yyyyy \
  --require-tls false


### Step 2: Register RDS Instance with Proxy

bash
# Get RDS instance identifier
aws rds describe-db-instances \
  --query 'DBInstances[*].[DBInstanceIdentifier]' \
  --output text

# Register target
aws rds register-db-proxy-targets \
  --db-proxy-name my-rds-proxy \
  --db-instance-identifiers my-postgres-db


### Step 3: Get RDS Proxy Endpoint

bash
# Get proxy endpoint
aws rds describe-db-proxies \
  --db-proxy-name my-rds-proxy \
  --query 'DBProxies[0].Endpoint' \
  --output text

# Output: my-rds-proxy.proxy-xxxxx.us-east-1.rds.amazonaws.com


### Step 4: Configure Security Groups

bash
# RDS Proxy Security Group - Allow from EC2
aws ec2 authorize-security-group-ingress \
  --group-id sg-proxy-xxxxx \
  --protocol tcp \
  --port 5432 \
  --source-group sg-ec2-xxxxx

# RDS Security Group - Allow from RDS Proxy
aws ec2 authorize-security-group-ingress \
  --group-id sg-rds-xxxxx \
  --protocol tcp \
  --port 5432 \
  --source-group sg-proxy-xxxxx


### Step 5: Install Node.js Dependencies on EC2

bash
# SSH into EC2
ssh ec2-user@your-ec2-ip

# Install Node.js (if not installed)
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo yum install -y nodejs

# Create project
mkdir my-app && cd my-app
npm init -y

# Install PostgreSQL client
npm install pg


### Step 6: JavaScript Application Code

Basic Connection:

javascript
const { Pool } = require('pg');

// Connect via RDS Proxy endpoint
const pool = new Pool({
  host: 'my-rds-proxy.proxy-xxxxx.us-east-1.rds.amazonaws.com',
  port: 5432,
  database: 'products_db',
  user: 'postgres',
  password: 'your-password',
  max: 20,                    // Max connections in pool
  idleTimeoutMillis: 30000,   // Close idle connections after 30s
  connectionTimeoutMillis: 2000
});

// Test connection
async function testConnection() {
  try {
    const client = await pool.connect();
    const result = await client.query('SELECT NOW()');
    console.log('Connected to RDS via Proxy:', result.rows[0]);
    client.release();
  } catch (error) {
    console.error('Connection error:', error);
  }
}

testConnection();


Complete CRUD Application:

javascript
const { Pool } = require('pg');
const express = require('express');

const app = express();
app.use(express.json());

// RDS Proxy connection pool
const pool = new Pool({
  host: process.env.DB_PROXY_ENDPOINT || 'my-rds-proxy.proxy-xxxxx.us-east-1.rds.amazonaws.com',
  port: 5432,
  database: process.env.DB_NAME || 'products_db',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000
});

// Health check
app.get('/health', async (req, res) => {
  try {
    const result = await pool.query('SELECT 1');
    res.json({ status: 'healthy', database: 'connected' });
  } catch (error) {
    res.status(500).json({ status: 'unhealthy', error: error.message });
  }
});

// Get all products
app.get('/products', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM products ORDER BY created_at DESC');
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get single product
app.get('/products/:id', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM products WHERE id = $1', [req.params.id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});
app.post('/products', async (req, res) => {
  const { name, price, category } = req.body;
  
  try {
    const result = await pool.query(
      'INSERT INTO products (name, price, category) VALUES ($1, $2, $3) RETURNING *',
      [name, price, category]
    );
    
    res.status(201).json(result.rows[0]);
  } catch (error) {
    res.status(500).json({ error: error.message });
app.put('/products/:id', async (req, res) => {
  const { name, price, category } = req.body;
  
  try {
    const result = await pool.query(
      'UPDATE products SET name = $1, price = $2, category = $3, updated_at = NOW() WHERE id = $4 RETURNING *',
      [name, price, category, req.params.id]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});products/:id', async (req, res) => {
  try {
    const result = await pool.query('DELETE FROM products WHERE id = $1 RETURNING *', [req.params.id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }
    
    res.status(204).send();
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, closing connections...');
  await pool.end();
  process.exit(0);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`Connected to RDS via Proxy: ${pool.options.host}`);
});


### Step 7: Environment Variables

Create .env file:

bash
DB_PROXY_ENDPOINT=my-rds-proxy.proxy-xxxxx.us-east-1.rds.amazonaws.com
DB_NAME=products_db
DB_USER=postgres
DB_PASSWORD=your-password
PORT=3000


Install dotenv:

bash
npm install dotenv


Load environment variables:

javascript
require('dotenv').config();

const pool = new Pool({
  host: process.env.DB_PROXY_ENDPOINT,
  port: 5432,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max: 20
});


### Step 8: Using Secrets Manager (Best Practice)

bash
# Install AWS SDK
npm install @aws-sdk/client-secrets-manager


javascript
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');
const { Pool } = require('pg');

const secretsClient = new SecretsManagerClient({ region: 'us-east-1' });

async function getDatabaseCredentials() {
  const command = new GetSecretValueCommand({
    SecretId: 'rds-db-credentials'
  });
  
  const response = await secretsClient.send(command);
  return JSON.parse(response.SecretString);
}

async function createPool() {
  const credentials = await getDatabaseCredentials();
  
  return new Pool({
    host: process.env.DB_PROXY_ENDPOINT,
    port: 5432,
    database: process.env.DB_NAME,
    user: credentials.username,
    password: credentials.password,
    max: 20
  });
}

// Initialize
let pool;
(async () => {
  pool = await createPool();
  console.log('Database pool created');
})();


### Step 9: Connection Pooling Best Practices

javascript
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_PROXY_ENDPOINT,
  port: 5432,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  
  // Pool configuration
  max: 20,                      // Max connections (RDS Proxy handles pooling)
  min: 2,                       // Min connections
  idleTimeoutMillis: 30000,     // Close idle connections after 30s
  connectionTimeoutMillis: 2000, // Timeout for new connections
  
  // Error handling
  allowExitOnIdle: false
});

// Monitor pool
pool.on('connect', () => {
  console.log('New client connected to pool');
});

pool.on('error', (err) => {
  console.error('Unexpected pool error:', err);
});

// Query with automatic connection management
async function queryDatabase(sql, params) {
  const client = await pool.connect();
  try {
    const result = await client.query(sql, params);
    return result.rows;
  } catch (error) {
    console.error('Query error:', error);
    throw error;
  } finally {
    client.release(); // Always release connection
  }
}


### Step 10: Run Application

bash
# Start application
node app.js

# Test endpoints
curl http://localhost:3000/health
curl http://localhost:3000/products


### Benefits of RDS Proxy

1. Connection Pooling:
- Reduces database connections
- Handles connection spikes
- Improves scalability

2. Failover:
- Automatic failover (< 30 seconds)
- Application doesn't need to reconnect

3. IAM Authentication (Optional):
javascript
const { Signer } = require('@aws-sdk/rds-signer');

const signer = new Signer({
  region: 'us-east-1',
  hostname: process.env.DB_PROXY_ENDPOINT,
  port: 5432,
  username: 'postgres'
});

const token = await signer.getAuthToken();

const pool = new Pool({
  host: process.env.DB_PROXY_ENDPOINT,
  port: 5432,
  database: process.env.DB_NAME,
  user: 'postgres',
  password: token,
  ssl: { rejectUnauthorized: false }
});


### Monitoring

bash
# Check RDS Proxy metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBProxyName,Value=my-rds-proxy \
  --start-time 2026-02-08T00:00:00Z \
  --end-time 2026-02-08T17:00:00Z \
  --period 3600 \
  --statistics Average


Your application now connects to RDS PostgreSQL through RDS Proxy with connection pooling and automatic 
failover.
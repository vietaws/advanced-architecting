import 'dotenv/config';
import express from 'express';
import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import http from 'http';
import { promises as fs } from 'fs';
import { DynamoDBClient, DescribeTableCommand } from '@aws-sdk/client-dynamodb';
import { SQSClient, GetQueueAttributesCommand } from '@aws-sdk/client-sqs';
import logger from './logger.js';
import productRoutes from './routes/products.js';
import providerRoutes from './routes/providers.js';
import stressRoutes from './routes/stress.js';
import efsRoutes from './routes/efs.js';
import orderRoutes from './routes/orders.js';

// __dirname is not available in ESM — reconstruct it
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// products-dax uses amazon-dax-client (CJS-only) — load via createRequire
const require = createRequire(import.meta.url);
const productsDaxRoutes = require('./routes/products-dax.cjs');

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(join(__dirname, 'public')));

app.use('/products', productRoutes);
app.use('/products-dax', productsDaxRoutes);
app.use('/providers', providerRoutes);
app.use('/stress', stressRoutes);
app.use('/efs', efsRoutes);
app.use('/orders', orderRoutes);

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.get('/health/status', async (req, res) => {
  const require = createRequire(import.meta.url);
  const results = await Promise.allSettled([

    // 1. DynamoDB — DescribeTable on products_table
    (async () => {
      const client = new DynamoDBClient({ region: process.env.AWS_REGION });
      await client.send(new DescribeTableCommand({ TableName: process.env.DYNAMODB_PRODUCTS_TABLE }));
      return { service: 'dynamodb', status: 'connected' };
    })(),

    // 2. Aurora (RDS PostgreSQL) — simple query
    (async () => {
      const { default: pool } = await import('./db/postgres.js');
      await pool.query('SELECT 1');
      return { service: 'aurora', status: 'connected' };
    })(),

    // 3. DAX — lightweight scan with Limit 1
    (async () => {
      const { daxClient, productsTableName } = require('./db/dax.cjs');
      await daxClient.scan({ TableName: productsTableName, Limit: 1 }).promise();
      return { service: 'dax', status: 'connected' };
    })(),

    // 4. SQS — GetQueueAttributes
    (async () => {
      const client = new SQSClient({ region: process.env.AWS_REGION });
      await client.send(new GetQueueAttributesCommand({
        QueueUrl: process.env.SQS_QUEUE_URL,
        AttributeNames: ['QueueArn']
      }));
      return { service: 'sqs', status: 'connected' };
    })(),

    // 5. EFS — check mount point is accessible and writable
    (async () => {
      const efsMountPoint = '/data/efs';
      await fs.access(efsMountPoint, fs.constants?.W_OK ?? 2);
      return { service: 'efs', status: 'connected' };
    })(),

    // 6. Stress — check running state from in-process status
    (async () => {
      const stressRes = await new Promise((resolve, reject) => {
        const port = process.env.PORT || 3001;
        http.get(`http://localhost:${port}/stress/status`, (r) => {
          let data = '';
          r.on('data', chunk => data += chunk);
          r.on('end', () => resolve(JSON.parse(data)));
        }).on('error', reject);
      });
      return { service: 'stress', status: stressRes.running ? 'running' : 'stopped' };
    })(),

  ]);

  const status = {};
  for (const result of results) {
    if (result.status === 'fulfilled') {
      const { service, status: svc_status } = result.value;
      status[service] = { status: svc_status };
    } else {
      // Extract service name from error context if possible
      const msg = result.reason?.message || 'unknown error';
      // Map error back to service by checking which promise index failed
      const idx = results.indexOf(result);
      const serviceNames = ['dynamodb', 'aurora', 'dax', 'sqs', 'efs', 'stress'];
      status[serviceNames[idx]] = { status: 'disconnected', error: msg };
    }
  }

  logger.info({ action: 'health.status', services: status }, 'Health status checked');
  res.json(status);
});

app.get('/instance-id', async (req, res) => {
  try {
    const token = await new Promise((resolve, reject) => {
      const req = http.request({
        host: '169.254.169.254',
        path: '/latest/api/token',
        method: 'PUT',
        headers: { 'X-aws-ec2-metadata-token-ttl-seconds': '21600' }
      }, (res) => {
        let data = '';
        res.on('data', (chunk) => data += chunk);
        res.on('end', () => resolve(data));
      });
      req.on('error', reject);
      req.end();
    });

    const instanceId = await new Promise((resolve, reject) => {
      http.get({
        host: '169.254.169.254',
        path: '/latest/meta-data/instance-id',
        headers: { 'X-aws-ec2-metadata-token': token }
      }, (res) => {
        let data = '';
        res.on('data', (chunk) => data += chunk);
        res.on('end', () => resolve(data));
      }).on('error', reject);
    });

    res.json({ instanceId });
  } catch (error) {
    res.json({ instanceId: 'local-dev' });
  }
});

app.use((err, req, res, next) => {
  logger.error({ err, url: req.url, method: req.method }, 'Unhandled error');
  res.status(500).json({ error: err.message });
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  logger.info({ port: PORT, env: process.env.NODE_ENV || 'production' }, 'Server started');
});

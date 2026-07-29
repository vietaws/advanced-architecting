import express from 'express';
import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { DynamoDBClient, DescribeTableCommand } from '@aws-sdk/client-dynamodb';
import { S3Client, HeadBucketCommand } from '@aws-sdk/client-s3';
import logger from './logger.js';
import productRoutes from './routes/products.js';

// ── CJS interop for DAX route (uses amazon-dax-client which is CJS) ──────────
const require = createRequire(import.meta.url);
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const productsDaxRoutes = require(join(__dirname, 'routes/products-dax.cjs'));

// ── App setup ─────────────────────────────────────────────────────────────────
const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// ── Routes ────────────────────────────────────────────────────────────────────
app.use('/products', productRoutes);
app.use('/products-dax', productsDaxRoutes);

// ── Health: liveness probe ────────────────────────────────────────────────────
app.get('/health', (_req, res) => {
  res.json({ status: 'healthy', service: 'product-service' });
});

// ── Health: deep status (DynamoDB + DAX + S3) ─────────────────────────────────
app.get('/health/status', async (_req, res) => {
  const results = await Promise.allSettled([

    // 1. DynamoDB — DescribeTable proves connectivity and table exists
    (async () => {
      const client = new DynamoDBClient({ region: process.env.AWS_REGION });
      await client.send(new DescribeTableCommand({
        TableName: process.env.DYNAMODB_PRODUCTS_TABLE
      }));
      return { service: 'dynamodb', status: 'connected' };
    })(),

    // 2. DAX — lightweight scan with Limit 1 via the DAX client
    (async () => {
      const AmazonDaxClient = require('amazon-dax-client');
      const client = new AmazonDaxClient({
        endpoints: [process.env.DAX_ENDPOINT],
        region: process.env.AWS_REGION
      });
      await client.scan({
        TableName: process.env.DYNAMODB_PRODUCTS_TABLE,
        Limit: 1
      }).promise();
      return { service: 'dax', status: 'connected' };
    })(),

    // 3. S3 — HeadBucket confirms bucket is accessible
    (async () => {
      const client = new S3Client({ region: process.env.AWS_REGION });
      await client.send(new HeadBucketCommand({ Bucket: process.env.S3_BUCKET }));
      return { service: 's3', status: 'connected' };
    })(),

  ]);

  const status = {};
  const serviceNames = ['dynamodb', 'dax', 's3'];

  for (let i = 0; i < results.length; i++) {
    const result = results[i];
    const name = serviceNames[i];
    if (result.status === 'fulfilled') {
      status[name] = { status: result.value.status };
    } else {
      logger.warn(
        { action: 'health.status', service: name, error: result.reason?.message },
        `${name} health check failed`
      );
      status[name] = { status: 'disconnected', error: result.reason?.message || 'unknown error' };
    }
  }

  logger.info({ action: 'health.status', services: status }, 'product-service health checked');
  res.json(status);
});

// ── Global error handler ──────────────────────────────────────────────────────
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  logger.error({ err: err.message, stack: err.stack }, 'Unhandled error');
  res.status(err.status || 500).json({ error: err.message || 'Internal Server Error' });
});

// ── Start ─────────────────────────────────────────────────────────────────────
const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  logger.info(
    {
      port: PORT,
      env: process.env.NODE_ENV || 'production',
      table: process.env.DYNAMODB_PRODUCTS_TABLE,
      bucket: process.env.S3_BUCKET,
      dax: process.env.DAX_ENDPOINT ? 'configured' : 'not configured',
    },
    'product-service started',
  );
});

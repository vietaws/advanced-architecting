import express from 'express';
import { DynamoDBClient, DescribeTableCommand } from '@aws-sdk/client-dynamodb';
import { SQSClient, GetQueueAttributesCommand } from '@aws-sdk/client-sqs';
import logger from './logger.js';
import orderRoutes from './routes/orders.js';

const app = express();
const PORT = process.env.PORT || 3003;

app.use(express.json());

// ── Routes ────────────────────────────────────────────────────────────────────
app.use('/orders', orderRoutes);

// ── Health: liveness probe ────────────────────────────────────────────────────
app.get(['/health', '/orders/health'], (_req, res) => {
  res.json({ status: 'healthy', service: 'order-service' });
});

// ── Health: deep status (SQS + DynamoDB) ─────────────────────────────────────
app.get(['/health/status', '/orders/health/status'], async (_req, res) => {
  const results = await Promise.allSettled([

    // 1. SQS — GetQueueAttributes confirms queue is reachable
    (async () => {
      const client = new SQSClient({ region: process.env.AWS_REGION });
      await client.send(new GetQueueAttributesCommand({
        QueueUrl: process.env.SQS_QUEUE_URL,
        AttributeNames: ['QueueArn']
      }));
      return { service: 'sqs', status: 'connected' };
    })(),

    // 2. DynamoDB — DescribeTable confirms orders table exists
    (async () => {
      const client = new DynamoDBClient({ region: process.env.AWS_REGION });
      await client.send(new DescribeTableCommand({
        TableName: process.env.DYNAMODB_ORDERS_TABLE
      }));
      return { service: 'dynamodb', status: 'connected' };
    })(),

  ]);

  const status = {};
  const serviceNames = ['sqs', 'dynamodb'];

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

  logger.info({ action: 'health.status', services: status }, 'order-service health checked');
  res.json(status);
});

// ── Global error handler ──────────────────────────────────────────────────────
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  logger.error({ err, path: _req?.path, method: _req?.method }, 'Unhandled error');
  res.status(500).json({ error: 'Internal server error' });
});

app.listen(PORT, () => {
  logger.info({ port: PORT, env: process.env.NODE_ENV }, 'order-service started');
});

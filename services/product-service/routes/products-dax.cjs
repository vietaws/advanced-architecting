const express = require('express');
const { daxClient, productsTableName } = require('../db/dax.cjs');
const { getImageUrl } = require('../db/s3');
const { unmarshall } = require('@aws-sdk/util-dynamodb');
const pino = require('pino');

const isDev = process.env.NODE_ENV === 'development';

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  base: { service: 'product-service' },
  transport: isDev
    ? { target: 'pino-pretty', options: { colorize: false, sync: true } }
    : undefined,
});

const router = express.Router();

// GET / — list all products via DAX cache
router.get('/', async (req, res) => {
  try {
    const startTime = process.hrtime.bigint();

    const result = await daxClient
      .scan({ TableName: productsTableName })
      .promise();

    const endTime = process.hrtime.bigint();
    // hrtime gives nanoseconds — convert to microseconds for DAX (sub-ms latency)
    const latency_us = Math.round(Number(endTime - startTime) / 1000);
    const latency_ms = (latency_us / 1000).toFixed(3);

    logger.info(
      {
        action: 'product.list',
        source: 'dax',
        count: result.Items?.length || 0,
        latency_us,
        latency_ms: parseFloat(latency_ms),
      },
      'DAX scan',
    );

    const items = (result.Items || []).map((item) => unmarshall(item));

    const products = await Promise.all(
      items.map(async (item) => ({
        ...item,
        image_url: await getImageUrl(item.image_key),
        responseTime: latency_us,
      })),
    );

    res.json(products);
  } catch (error) {
    logger.error({ action: 'product.list', source: 'dax', error: error.message }, 'DAX scan failed');
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;

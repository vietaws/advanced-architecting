const express = require('express');
const { daxClient, productsTableName } = require('../db/dax');
const { getImageUrl } = require('../db/s3');
const { unmarshall } = require('@aws-sdk/util-dynamodb');
// Load the ESM logger via a synchronous-compatible shim using pino directly in CJS
const pino = require('pino');

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  base: { service: 'architecting-pro' }
});

const router = express.Router();

router.get('/', async (req, res) => {
  try {
    const startTime = process.hrtime.bigint();

    const result = await daxClient.scan({
      TableName: productsTableName
    }).promise();

    const endTime = process.hrtime.bigint();
    // hrtime gives nanoseconds — convert to microseconds for DAX (sub-ms latency)
    const latency_us = Number(endTime - startTime) / 1000;

    logger.info(
      { action: 'product.list', source: 'dax', count: result.Items?.length || 0, latency_us: Math.round(latency_us) },
      'DAX scan'
    );

    const items = (result.Items || []).map(item => unmarshall(item));

    const products = await Promise.all(items.map(async (item) => ({
      ...item,
      image_url: await getImageUrl(item.image_key),
      responseTime: Math.round(latency_us)
    })));

    res.json(products);
  } catch (error) {
    logger.error({ action: 'product.list', source: 'dax', error: error.message }, 'DAX scan failed');
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;

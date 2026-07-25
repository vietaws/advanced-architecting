const express = require('express');
const { daxClient, productsTableName } = require('../db/dax');
const { getImageUrl } = require('../db/s3');
const { unmarshall } = require('@aws-sdk/util-dynamodb');
const router = express.Router();

router.get('/', async (req, res) => {
  try {
    console.log('Products-DAX: Scanning table:', productsTableName);
    const startTime = process.hrtime.bigint();
    
    const result = await daxClient.scan({
      TableName: productsTableName
    }).promise();
    
    const endTime = process.hrtime.bigint();
    const responseTime = Number(endTime - startTime) / 1000; // Convert nanoseconds to microseconds
    
    console.log('Products-DAX: Found', result.Items?.length || 0, 'items in', responseTime.toFixed(0), 'μs');
    
    // Unmarshall DynamoDB format to plain JavaScript objects
    const items = (result.Items || []).map(item => unmarshall(item));
    
    const products = await Promise.all(items.map(async (item) => ({
      ...item,
      image_url: await getImageUrl(item.image_key),
      responseTime: Math.round(responseTime)
    })));
    res.json(products);
  } catch (error) {
    console.error('Products-DAX error:', error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;


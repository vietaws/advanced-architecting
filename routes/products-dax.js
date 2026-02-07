const express = require('express');
const { daxDocClient, ScanCommand, productsTableName } = require('../db/dax');
const { getImageUrl } = require('../db/s3');
const router = express.Router();

router.get('/', async (req, res) => {
  try {
    console.log('Products-DAX: Scanning table:', productsTableName);
    const startTime = Date.now();
    const result = await daxDocClient.send(new ScanCommand({ TableName: productsTableName }));
    const responseTime = Date.now() - startTime;
    
    console.log('Products-DAX: Found', result.Items?.length || 0, 'items in', responseTime, 'ms');
    
    const products = await Promise.all((result.Items || []).map(async (item) => ({
      ...item,
      image_url: await getImageUrl(item.image_key),
      responseTime: responseTime
    })));
    res.json(products);
  } catch (error) {
    console.error('Products-DAX error:', error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;

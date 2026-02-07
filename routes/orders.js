const express = require('express');
const { sendOrder } = require('../db/sqs');
const { docClient, ScanCommand } = require('../db/dynamodb');
const config = require('../app_config.json');
const router = express.Router();

const PRODUCT_NAMES = ['Laptop', 'Mouse', 'Keyboard', 'Monitor', 'Headset', 'Webcam', 'Desk', 'Chair'];

function generateOrder() {
  return {
    id: `ORD-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
    product_name: PRODUCT_NAMES[Math.floor(Math.random() * PRODUCT_NAMES.length)],
    qty: Math.floor(Math.random() * 10) + 1,
    price: (Math.random() * 1000 + 10).toFixed(2),
    customer_id: `CUST-${Math.floor(Math.random() * 10000)}`,
    status: 'in-processing',
    time: new Date().toISOString()
  };
}

router.post('/generate', async (req, res) => {
  try {
    const orders = [];
    for (let i = 0; i < 10; i++) {
      const order = generateOrder();
      await sendOrder(order);
      orders.push(order);
    }
    res.json({ message: '10 orders sent to SQS', count: orders.length });
  } catch (error) {
    console.error('Order generation error:', error);
    res.status(500).json({ error: error.message });
  }
});

router.get('/', async (req, res) => {
  try {
    const result = await docClient.send(new ScanCommand({ 
      TableName: config.dynamodb.ordersTableName 
    }));
    res.json(result.Items || []);
  } catch (error) {
    console.error('Order fetch error:', error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;

import express from 'express';
import { sendOrder } from '../db/sqs.js';
import { docClient, ScanCommand, ordersTableName } from '../db/dynamodb.js';
import logger from '../logger.js';

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
      logger.info(
        { action: 'order.sent', order_id: order.id, product: order.product_name, qty: order.qty, customer_id: order.customer_id },
        'Order sent to SQS'
      );
    }

    logger.info({ action: 'order.batch', count: orders.length }, 'Order batch sent to SQS');
    res.json({ message: '10 orders sent to SQS', count: orders.length });
  } catch (error) {
    logger.error({ action: 'order.sent', error: error.message }, 'Failed to send order to SQS');
    res.status(500).json({ error: error.message });
  }
});

router.get('/', async (req, res) => {
  try {
    const result = await docClient.send(new ScanCommand({
      TableName: ordersTableName
    }));
    res.json(result.Items || []);
  } catch (error) {
    logger.error({ action: 'order.list', error: error.message }, 'Failed to fetch orders');
    res.status(500).json({ error: error.message });
  }
});

export default router;

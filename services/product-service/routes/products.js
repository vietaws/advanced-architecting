import express from 'express';
import multer from 'multer';
import { randomUUID } from 'crypto';
import {
  docClient,
  PutCommand,
  GetCommand,
  UpdateCommand,
  DeleteCommand,
  ScanCommand,
  productsTableName,
} from '../db/dynamodb.js';
import { uploadImage, getImageUrl, deleteImage } from '../db/s3.js';
import logger from '../logger.js';

const router = express.Router();
const upload = multer({ storage: multer.memoryStorage() });

// POST / — create product
router.post('/', upload.single('image'), async (req, res) => {
  try {
    const { product_name, description, price, remaining_sku } = req.body;
    const id = req.body.id || randomUUID();

    if (!product_name) {
      return res.status(400).json({ error: 'product_name is required' });
    }

    let image_key = '';
    if (req.file) {
      image_key = await uploadImage(req.file, id);
    }

    const startTime = Date.now();
    await docClient.send(new PutCommand({
      TableName: productsTableName,
      Item: {
        id,
        product_name,
        description: description || '',
        image_key,
        price: price ? parseFloat(price) : 0,
        remaining_sku: remaining_sku ? parseInt(remaining_sku) : 0,
      },
    }));
    const latency_ms = Date.now() - startTime;

    const image_url = image_key ? await getImageUrl(image_key) : '';

    logger.info(
      { action: 'product.create', source: 'dynamodb', id, product_name, has_image: !!image_key, latency_ms },
      'Product created',
    );

    res.json({ message: 'Product created', id, image_url });
  } catch (error) {
    logger.error({ action: 'product.create', error: error.message }, 'Failed to create product');
    res.status(500).json({ error: error.message });
  }
});

// GET / — list all products
router.get('/', async (req, res) => {
  try {
    const startTime = Date.now();
    const result = await docClient.send(new ScanCommand({ TableName: productsTableName }));
    const latency_ms = Date.now() - startTime;

    logger.info(
      { action: 'product.list', source: 'dynamodb', count: result.Items.length, latency_ms },
      'DynamoDB scan',
    );

    const products = await Promise.all(
      result.Items.map(async (item) => ({
        ...item,
        image_url: await getImageUrl(item.image_key),
        responseTime: latency_ms,
      })),
    );

    res.json(products);
  } catch (error) {
    logger.error({ action: 'product.list', source: 'dynamodb', error: error.message }, 'Failed to list products');
    res.status(500).json({ error: error.message });
  }
});

// GET /:id — get product by ID
router.get('/:id', async (req, res) => {
  try {
    const startTime = Date.now();
    const result = await docClient.send(
      new GetCommand({
        TableName: productsTableName,
        Key: { id: req.params.id },
      }),
    );
    const latency_ms = Date.now() - startTime;

    logger.info(
      { action: 'product.get', source: 'dynamodb', id: req.params.id, found: !!result.Item, latency_ms },
      'DynamoDB get',
    );

    if (!result.Item) return res.status(404).json({ error: 'Product not found' });

    result.Item.image_url = await getImageUrl(result.Item.image_key);
    res.json(result.Item);
  } catch (error) {
    logger.error(
      { action: 'product.get', source: 'dynamodb', id: req.params.id, error: error.message },
      'Failed to get product',
    );
    res.status(500).json({ error: error.message });
  }
});

// PUT /:id — update product
router.put('/:id', async (req, res) => {
  try {
    const { product_name, description, price, remaining_sku } = req.body;
    const startTime = Date.now();

    await docClient.send(
      new UpdateCommand({
        TableName: productsTableName,
        Key: { id: req.params.id },
        UpdateExpression: 'set product_name = :n, description = :d, price = :p, remaining_sku = :s',
        ExpressionAttributeValues: {
          ':n': product_name,
          ':d': description,
          ':p': price,
          ':s': remaining_sku,
        },
      }),
    );
    const latency_ms = Date.now() - startTime;

    logger.info(
      { action: 'product.update', source: 'dynamodb', id: req.params.id, product_name, latency_ms },
      'Product updated',
    );

    res.json({ message: 'Product updated' });
  } catch (error) {
    logger.error({ action: 'product.update', id: req.params.id, error: error.message }, 'Failed to update product');
    res.status(500).json({ error: error.message });
  }
});

// DELETE /:id — delete product + S3 image
router.delete('/:id', async (req, res) => {
  try {
    const startTime = Date.now();
    const result = await docClient.send(
      new DeleteCommand({
        TableName: productsTableName,
        Key: { id: req.params.id },
        ReturnValues: 'ALL_OLD',
      }),
    );
    const latency_ms = Date.now() - startTime;

    if (result.Attributes?.image_key) {
      await deleteImage(result.Attributes.image_key);
    }

    logger.info(
      { action: 'product.delete', source: 'dynamodb', id: req.params.id, latency_ms },
      'Product deleted',
    );

    res.json({ message: 'Product deleted' });
  } catch (error) {
    logger.error({ action: 'product.delete', id: req.params.id, error: error.message }, 'Failed to delete product');
    res.status(500).json({ error: error.message });
  }
});

export default router;

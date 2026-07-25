import express from 'express';
import multer from 'multer';
import {
  docClient,
  PutCommand,
  GetCommand,
  UpdateCommand,
  DeleteCommand,
  ScanCommand,
  productsTableName
} from '../db/dynamodb.js';
import { uploadImage, getImageUrl, deleteImage } from '../db/s3.js';

const router = express.Router();
const upload = multer({ storage: multer.memoryStorage() });

router.post('/', upload.single('image'), async (req, res) => {
  try {
    const { id, product_name, description, price, remaining_sku } = req.body;

    if (!id || !product_name) {
      return res.status(400).json({ error: 'id and product_name are required' });
    }

    let image_key = '';
    if (req.file) {
      image_key = await uploadImage(req.file, id);
    }

    await docClient.send(new PutCommand({
      TableName: productsTableName,
      Item: {
        id,
        product_name,
        description: description || '',
        image_key,
        price: price ? parseFloat(price) : 0,
        remaining_sku: remaining_sku ? parseInt(remaining_sku) : 0
      }
    }));

    const image_url = image_key ? await getImageUrl(image_key) : '';
    res.json({ message: 'Product created', id, image_url });
  } catch (error) {
    console.error('Product creation error:', error);
    res.status(500).json({ error: error.message });
  }
});

router.get('/', async (req, res) => {
  try {
    const startTime = Date.now();
    const result = await docClient.send(new ScanCommand({ TableName: productsTableName }));
    const responseTime = Date.now() - startTime;

    const products = await Promise.all(result.Items.map(async (item) => ({
      ...item,
      image_url: await getImageUrl(item.image_key),
      responseTime
    })));
    res.json(products);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const result = await docClient.send(new GetCommand({
      TableName: productsTableName,
      Key: { id: req.params.id }
    }));
    if (result.Item) {
      result.Item.image_url = await getImageUrl(result.Item.image_key);
    }
    res.json(result.Item || {});
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const { product_name, description, price, remaining_sku } = req.body;
    await docClient.send(new UpdateCommand({
      TableName: productsTableName,
      Key: { id: req.params.id },
      UpdateExpression: 'set product_name = :n, description = :d, price = :p, remaining_sku = :s',
      ExpressionAttributeValues: { ':n': product_name, ':d': description, ':p': price, ':s': remaining_sku }
    }));
    res.json({ message: 'Product updated' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const result = await docClient.send(new GetCommand({
      TableName: productsTableName,
      Key: { id: req.params.id }
    }));

    if (result.Item?.image_key) {
      await deleteImage(result.Item.image_key);
    }

    await docClient.send(new DeleteCommand({
      TableName: productsTableName,
      Key: { id: req.params.id }
    }));

    res.json({ message: 'Product deleted' });
  } catch (error) {
    console.error('Product deletion error:', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;

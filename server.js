import 'dotenv/config';
import express from 'express';
import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import http from 'http';
import productRoutes from './routes/products.js';
import providerRoutes from './routes/providers.js';
import stressRoutes from './routes/stress.js';
import efsRoutes from './routes/efs.js';
import orderRoutes from './routes/orders.js';

// __dirname is not available in ESM — reconstruct it
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// products-dax uses amazon-dax-client (CJS-only) — load via createRequire
const require = createRequire(import.meta.url);
const productsDaxRoutes = require('./routes/products-dax.cjs');

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(join(__dirname, 'public')));

app.use('/products', productRoutes);
app.use('/products-dax', productsDaxRoutes);
app.use('/providers', providerRoutes);
app.use('/stress', stressRoutes);
app.use('/efs', efsRoutes);
app.use('/orders', orderRoutes);

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.get('/instance-id', async (req, res) => {
  try {
    const token = await new Promise((resolve, reject) => {
      const req = http.request({
        host: '169.254.169.254',
        path: '/latest/api/token',
        method: 'PUT',
        headers: { 'X-aws-ec2-metadata-token-ttl-seconds': '21600' }
      }, (res) => {
        let data = '';
        res.on('data', (chunk) => data += chunk);
        res.on('end', () => resolve(data));
      });
      req.on('error', reject);
      req.end();
    });

    const instanceId = await new Promise((resolve, reject) => {
      http.get({
        host: '169.254.169.254',
        path: '/latest/meta-data/instance-id',
        headers: { 'X-aws-ec2-metadata-token': token }
      }, (res) => {
        let data = '';
        res.on('data', (chunk) => data += chunk);
        res.on('end', () => resolve(data));
      }).on('error', reject);
    });

    res.json({ instanceId });
  } catch (error) {
    res.json({ instanceId: 'local-dev' });
  }
});

app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(500).json({ error: err.message });
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});

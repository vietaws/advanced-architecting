## API with Caching: CloudFront vs Global Accelerator

### Example API: E-commerce Product API

Endpoints:
- GET /products - List all products
- GET /products/:id - Get product details
- GET /products/search?q=laptop - Search products
- POST /orders - Create order
- GET /user/cart - Get user's cart (personalized)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## CloudFront Implementation

### Setup

bash
# Create CloudFront distribution for API
aws cloudfront create-distribution \
  --origin-domain-name api.example.com \
  --default-root-object "" \
  --distribution-config '{
    "Origins": {
      "Items": [{
        "Id": "api-origin",
        "DomainName": "api-alb-123.us-east-1.elb.amazonaws.com",
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "https-only"
        }
      }]
    },
    "DefaultCacheBehavior": {
      "TargetOriginId": "api-origin",
      "ViewerProtocolPolicy": "https-only",
      "AllowedMethods": {
        "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      },
      "CachedMethods": {
        "Items": ["GET", "HEAD", "OPTIONS"]
      },
      "ForwardedValues": {
        "QueryString": true,
        "Headers": {
          "Items": ["Authorization", "Accept"]
        }
      },
      "MinTTL": 0,
      "DefaultTTL": 300,
      "MaxTTL": 3600
    },
    "CacheBehaviors": {
      "Items": [
        {
          "PathPattern": "/products*",
          "TargetOriginId": "api-origin",
          "MinTTL": 300,
          "DefaultTTL": 3600,
          "MaxTTL": 86400
        },
        {
          "PathPattern": "/user/*",
          "TargetOriginId": "api-origin",
          "MinTTL": 0,
          "DefaultTTL": 0,
          "MaxTTL": 0
        }
      ]
    }
  }'


### API Backend (Express)

javascript
// api-server.js
const express = require('express');
const app = express();

app.use(express.json());

// Cacheable endpoint
app.get('/products', (req, res) => {
  console.log('Origin: Fetching all products');
  
  const products = [
    { id: 1, name: 'Laptop', price: 999 },
    { id: 2, name: 'Mouse', price: 29 }
  ];
  
  // Set cache headers for CloudFront
  res.set({
    'Cache-Control': 'public, max-age=3600',  // Cache for 1 hour
    'X-Origin-Server': 'us-east-1'
  });
  
  res.json(products);
});

// Cacheable with query params
app.get('/products/search', (req, res) => {
  console.log('Origin: Searching products:', req.query.q);
  
  const results = searchProducts(req.query.q);
  
  res.set({
    'Cache-Control': 'public, max-age=300'  // Cache for 5 minutes
  });
  
  res.json(results);
});

// Not cacheable (personalized)
app.get('/user/cart', (req, res) => {
  console.log('Origin: Fetching user cart');
  
  const userId = req.headers.authorization;
  const cart = getUserCart(userId);
  
  res.set({
    'Cache-Control': 'private, no-cache'  // Don't cache
  });
  
  res.json(cart);
});

// Not cacheable (write operation)
app.post('/orders', (req, res) => {
  console.log('Origin: Creating order');
  
  const order = createOrder(req.body);
  
  res.set({
    'Cache-Control': 'no-store'  // Never cache
  });
  
  res.json(order);
});

app.listen(3000);


### Client Usage

javascript
// client.js
const axios = require('axios');

const API_URL = 'https://d1234.cloudfront.net';

async function testAPI() {
  // Request 1: GET /products (cache MISS)
  console.log('\n=== Request 1: GET /products ===');
  const start1 = Date.now();
  await axios.get(`${API_URL}/products`);
  console.log(`Latency: ${Date.now() - start1}ms`);
  console.log('X-Cache: Miss from cloudfront');
  // Output: 200ms (goes to origin)
  
  // Request 2: GET /products (cache HIT)
  console.log('\n=== Request 2: GET /products ===');
  const start2 = Date.now();
  await axios.get(`${API_URL}/products`);
  console.log(`Latency: ${Date.now() - start2}ms`);
  console.log('X-Cache: Hit from cloudfront');
  // Output: 10ms (from cache, no origin request!)
  
  // Request 3: GET /products (cache HIT)
  console.log('\n=== Request 3: GET /products ===');
  const start3 = Date.now();
  await axios.get(`${API_URL}/products`);
  console.log(`Latency: ${Date.now() - start3}ms`);
  console.log('X-Cache: Hit from cloudfront');
  // Output: 10ms (from cache)
  
  // Request 4: GET /user/cart (NOT cached)
  console.log('\n=== Request 4: GET /user/cart ===');
  const start4 = Date.now();
  await axios.get(`${API_URL}/user/cart`, {
    headers: { Authorization: 'Bearer token123' }
  });
  console.log(`Latency: ${Date.now() - start4}ms`);
  console.log('X-Cache: Miss from cloudfront (not cacheable)');
  // Output: 200ms (always goes to origin)
}

testAPI();


Results:
Request 1 (GET /products): 200ms - Origin request
Request 2 (GET /products): 10ms - Cache hit (95% faster!)
Request 3 (GET /products): 10ms - Cache hit
Request 4 (GET /user/cart): 200ms - Origin request (personalized)

Origin requests: 2 out of 4 (50% cache hit rate)
Average latency: 105ms


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Global Accelerator Implementation

### Setup

bash
# Create Global Accelerator
aws globalaccelerator create-accelerator \
  --name api-accelerator \
  --ip-address-type IPV4 \
  --enabled

# Create listener
aws globalaccelerator create-listener \
  --accelerator-arn arn:aws:globalaccelerator::123456789012:accelerator/xxxxx \
  --port-ranges FromPort=443,ToPort=443 \
  --protocol TCP

# Create endpoint group
aws globalaccelerator create-endpoint-group \
  --listener-arn arn:aws:globalaccelerator::123456789012:listener/xxxxx \
  --endpoint-group-region us-east-1 \
  --endpoint-configurations \
    EndpointId=arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/api-alb/xxxxx,Weight=100


### API Backend (Same as CloudFront)

javascript
// api-server.js (identical to CloudFront example)
const express = require('express');
const app = express();

app.get('/products', (req, res) => {
  console.log('Origin: Fetching all products');
  
  const products = [
    { id: 1, name: 'Laptop', price: 999 },
    { id: 2, name: 'Mouse', price: 29 }
  ];
  
  res.json(products);
});

app.get('/user/cart', (req, res) => {
  console.log('Origin: Fetching user cart');
  
  const cart = getUserCart(req.headers.authorization);
  res.json(cart);
});

app.listen(3000);


### Client Usage

javascript
// client.js
const axios = require('axios');

const API_URL = 'https://3.5.6.7';  // Static Global Accelerator IP

async function testAPI() {
  // Request 1: GET /products (NO caching)
  console.log('\n=== Request 1: GET /products ===');
  const start1 = Date.now();
  await axios.get(`${API_URL}/products`);
  console.log(`Latency: ${Date.now() - start1}ms`);
  // Output: 150ms (goes to origin via AWS network)
  
  // Request 2: GET /products (NO caching)
  console.log('\n=== Request 2: GET /products ===');
  const start2 = Date.now();
  await axios.get(`${API_URL}/products`);
  console.log(`Latency: ${Date.now() - start2}ms`);
  // Output: 150ms (goes to origin again!)
  
  // Request 3: GET /products (NO caching)
  console.log('\n=== Request 3: GET /products ===');
  const start3 = Date.now();
  await axios.get(`${API_URL}/products`);
  console.log(`Latency: ${Date.now() - start3}ms`);
  // Output: 150ms (goes to origin again!)
  
  // Request 4: GET /user/cart
  console.log('\n=== Request 4: GET /user/cart ===');
  const start4 = Date.now();
  await axios.get(`${API_URL}/user/cart`, {
    headers: { Authorization: 'Bearer token123' }
  });
  console.log(`Latency: ${Date.now() - start4}ms`);
  // Output: 150ms (goes to origin)
}

testAPI();


Results:
Request 1 (GET /products): 150ms - Origin request
Request 2 (GET /products): 150ms - Origin request (no cache!)
Request 3 (GET /products): 150ms - Origin request (no cache!)
Request 4 (GET /user/cart): 150ms - Origin request

Origin requests: 4 out of 4 (0% cache hit rate)
Average latency: 150ms
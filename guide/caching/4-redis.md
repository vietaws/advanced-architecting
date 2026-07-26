 ## ElastiCache Redis Caching Strategy for Node.js

### Step 1: Install Dependencies

bash
npm install redis pg


### Step 2: Complete Caching Implementation

javascript
const { createClient } = require('redis');
const { Pool } = require('pg');

// Redis client
const redis = createClient({
  socket: {
    host: 'my-redis-cluster.xxxxx.cache.amazonaws.com',
    port: 6379
  }
});

redis.on('error', (err) => console.error('Redis error:', err));
redis.connect();

// PostgreSQL client
const pgPool = new Pool({
  host: 'my-db.xxxxx.us-east-1.rds.amazonaws.com',
  port: 5432,
  database: 'products_db',
  user: 'admin',
  password: 'your-password',
  max: 20
});

const CACHE_TTL = 3600; // 1 hour

// Strategy 1: Cache-Aside (Lazy Loading)
async function getProduct(productId) {
  const cacheKey = `product:${productId}`;
  
  try {
    // Try cache first
    const cached = await redis.get(cacheKey);
    
    if (cached) {
      console.log('Cache HIT');
      return JSON.parse(cached);
    }
    
    console.log('Cache MISS');
    
    // Query database
    const result = await pgPool.query(
      'SELECT * FROM products WHERE id = $1',
      [productId]
    );
    
    if (result.rows.length === 0) {
      return null;
    }
    
    const product = result.rows[0];
    
    // Store in cache
    await redis.setEx(cacheKey, CACHE_TTL, JSON.stringify(product));
    
    return product;
    
  } catch (error) {
    console.error('Error getting product:', error);
    throw error;
  }
}

// Strategy 2: Write-Through Cache
async function createProduct(product) {
  const cacheKey = `product:${product.id}`;
  
  try {
    // Write to database
    const result = await pgPool.query(
      'INSERT INTO products (id, name, price, category) VALUES ($1, $2, $3, $4) RETURNING *',
      [product.id, product.name, product.price, product.category]
    );
    
    const newProduct = result.rows[0];
    
    // Write to cache
    await redis.setEx(cacheKey, CACHE_TTL, JSON.stringify(newProduct));
    
    console.log('Product created and cached');
    return newProduct;
    
  } catch (error) {
    console.error('Error creating product:', error);
    throw error;
  }
}

// Strategy 3: Cache Invalidation on Update
async function updateProduct(productId, updates) {
  const cacheKey = `product:${productId}`;
  
  try {
    // Update database
    const result = await pgPool.query(
      'UPDATE products SET name = $1, price = $2, updated_at = NOW() WHERE id = $3 RETURNING *',
      [updates.name, updates.price, productId]
    );
    
    if (result.rows.length === 0) {
      return null;
    }
    
    const updatedProduct = result.rows[0];
    
    // Invalidate cache (delete old)
    await redis.del(cacheKey);
    
    // Or update cache (write-through)
    await redis.setEx(cacheKey, CACHE_TTL, JSON.stringify(updatedProduct));
    
    console.log('Product updated, cache refreshed');
    return updatedProduct;
    
  } catch (error) {
    console.error('Error updating product:', error);
    throw error;
  }
}

// Strategy 4: Delete with Cache Invalidation
async function deleteProduct(productId) {
  const cacheKey = `product:${productId}`;
  
  try {
    // Delete from database
    await pgPool.query('DELETE FROM products WHERE id = $1', [productId]);
    
    // Delete from cache
    await redis.del(cacheKey);
    
    console.log('Product deleted from DB and cache');
    
  } catch (error) {
    console.error('Error deleting product:', error);
    throw error;
  }
}

// Strategy 5: Batch Get with Caching
async function getMultipleProducts(productIds) {
  const cacheKeys = productIds.map(id => `product:${id}`);
  
  try {
    // Try to get all from cache
    const cachedResults = await redis.mGet(cacheKeys);
    
    const products = [];
    const missingIds = [];
    
    cachedResults.forEach((cached, index) => {
      if (cached) {
        products.push(JSON.parse(cached));
      } else {
        missingIds.push(productIds[index]);
      }
    });
    
    // Fetch missing from database
    if (missingIds.length > 0) {
      const result = await pgPool.query(
        'SELECT * FROM products WHERE id = ANY($1)',
        [missingIds]
      );
      
      // Cache the missing items
      for (const product of result.rows) {
        await redis.setEx(
          `product:${product.id}`,
          CACHE_TTL,
          JSON.stringify(product)
        );
        products.push(product);
      }
    }
    
    return products;
    
  } catch (error) {
    console.error('Error getting multiple products:', error);
    throw error;
  }
}

// Strategy 6: Query Results Caching
async function getProductsByCategory(category) {
  const cacheKey = `products:category:${category}`;
  
  try {
    // Try cache
    const cached = await redis.get(cacheKey);
    
    if (cached) {
      console.log('Cache HIT for category');
      return JSON.parse(cached);
    }
    
    console.log('Cache MISS for category');
    
    // Query database
    const result = await pgPool.query(
      'SELECT * FROM products WHERE category = $1 ORDER BY created_at DESC',
      [category]
    );
    
    const products = result.rows;
    
    // Cache results (shorter TTL for lists)
    await redis.setEx(cacheKey, 300, JSON.stringify(products)); // 5 minutes
    
    return products;
    
  } catch (error) {
    console.error('Error getting products by category:', error);
    throw error;
  }
}

// Strategy 7: Invalidate Related Caches
async function invalidateCategoryCache(category) {
  const cacheKey = `products:category:${category}`;
  await redis.del(cacheKey);
  console.log(`Invalidated cache for category: ${category}`);
}

// Strategy 8: Cache with Fallback
async function getProductWithFallback(productId) {
  const cacheKey = `product:${productId}`;
  
  try {
    // Try Redis
    const cached = await redis.get(cacheKey);
    if (cached) return JSON.parse(cached);
    
  } catch (redisError) {
    console.warn('Redis unavailable, querying DB directly');
  }
  
  // Fallback to database
  const result = await pgPool.query(
    'SELECT * FROM products WHERE id = $1',
    [productId]
  );
  
  return result.rows[0] || null;
}

// Strategy 9: Cache Warming
async function warmCache() {
  console.log('Warming cache with popular products...');
  
  try {
    // Get popular products
    const result = await pgPool.query(
      'SELECT * FROM products ORDER BY views DESC LIMIT 100'
    );
    
    // Cache them
    for (const product of result.rows) {
      await redis.setEx(
        `product:${product.id}`,
        CACHE_TTL,
        JSON.stringify(product)
      );
    }
    
    console.log(`Cached ${result.rows.length} popular products`);
    
  } catch (error) {
    console.error('Error warming cache:', error);
  }
}

// Strategy 10: Increment Counter (Redis native)
async function incrementProductViews(productId) {
  const counterKey = `product:${productId}:views`;
  
  try {
    // Increment in Redis
    const views = await redis.incr(counterKey);
    
    // Periodically sync to database (every 100 views)
    if (views % 100 === 0) {
      await pgPool.query(
        'UPDATE products SET views = views + 100 WHERE id = $1',
        [productId]
      );
    }
    
    return views;
    
  } catch (error) {
    console.error('Error incrementing views:', error);
    throw error;
  }
}

module.exports = {
  getProduct,
  createProduct,
  updateProduct,
  deleteProduct,
  getMultipleProducts,
  getProductsByCategory,
  invalidateCategoryCache,
  getProductWithFallback,
  warmCache,
  incrementProductViews
};


### Step 3: Express API with Redis Caching

javascript
const express = require('express');
const {
  getProduct,
  createProduct,
  updateProduct,
  deleteProduct,
  getProductsByCategory,
  invalidateCategoryCache,
  incrementProductViews
} = require('./cache-service');

const app = express();
app.use(express.json());

// Get product (cached)
app.get('/products/:id', async (req, res) => {
  try {
    const product = await getProduct(req.params.id);
    
    if (!product) {
      return res.status(404).json({ error: 'Product not found' });
    }
    
    // Increment views
    await incrementProductViews(req.params.id);
    
    res.json(product);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Create product
app.post('/products', async (req, res) => {
  try {
    const product = await createProduct(req.body);
    
    // Invalidate category cache
    await invalidateCategoryCache(product.category);
    
    res.status(201).json(product);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Update product
app.put('/products/:id', async (req, res) => {
  try {
    const product = await updateProduct(req.params.id, req.body);
    
    if (!product) {
      return res.status(404).json({ error: 'Product not found' });
    }
    
    // Invalidate category cache
    await invalidateCategoryCache(product.category);
    
    res.json(product);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Delete product
app.delete('/products/:id', async (req, res) => {
  try {
    await deleteProduct(req.params.id);
    res.status(204).send();
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get by category (cached)
app.get('/products/category/:category', async (req, res) => {
  try {
    const products = await getProductsByCategory(req.params.category);
    res.json(products);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(3000, () => {
  console.log('Server running on port 3000');
});


### Step 4: Environment Configuration

javascript
// config.js
module.exports = {
  redis: {
    host: process.env.REDIS_HOST || 'localhost',
    port: process.env.REDIS_PORT || 6379
  },
  postgres: {
    host: process.env.DB_HOST,
    port: process.env.DB_PORT || 5432,
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD
  },
  cache: {
    ttl: process.env.CACHE_TTL || 3600
  }
};


### Step 5: Security Group Configuration

bash
# EC2 Security Group - Allow outbound to Redis and RDS
aws ec2 authorize-security-group-egress \
  --group-id sg-ec2-xxxxx \
  --protocol tcp \
  --port 6379 \
  --destination-group sg-redis-xxxxx

aws ec2 authorize-security-group-egress \
  --group-id sg-ec2-xxxxx \
  --protocol tcp \
  --port 5432 \
  --destination-group sg-rds-xxxxx

# Redis Security Group - Allow inbound from EC2
aws ec2 authorize-security-group-ingress \
  --group-id sg-redis-xxxxx \
  --protocol tcp \
  --port 6379 \
  --source-group sg-ec2-xxxxx

# RDS Security Group - Allow inbound from EC2
aws ec2 authorize-security-group-ingress \
  --group-id sg-rds-xxxxx \
  --protocol tcp \
  --port 5432 \
  --source-group sg-ec2-xxxxx


### Caching Strategies Summary

| Strategy | Use Case | TTL |
|----------|----------|-----|
| Cache-Aside | Read-heavy data | 1 hour |
| Write-Through | Consistency critical | 1 hour |
| Cache Invalidation | Updates | Immediate |
| Query Caching | List/search results | 5 minutes |
| Counter Caching | Views, likes | No expiry |
| Batch Operations | Multiple items | 1 hour |

This implementation provides optimal caching with Redis while maintaining data consistency with 
PostgreSQL.


## When ElastiCache Redis Memory is Full

### What Happens

Redis uses an eviction policy to handle full memory. Behavior depends on your configured policy:

### Eviction Policies

1. noeviction (Default)
- Redis returns errors for write operations
- Error: OOM command not allowed when used memory > 'maxmemory'
- Reads still work
- **Your app will fail to cache new data**

2. allkeys-lru (Recommended)
- Evicts least recently used (LRU) keys
- Works across all keys
- New data can be cached
- Oldest data is removed automatically

3. volatile-lru
- Evicts LRU keys with TTL set
- If no keys have TTL, behaves like noeviction

4. allkeys-lfu
- Evicts least frequently used keys
- Better for access patterns with frequency differences

5. volatile-lfu
- Evicts LFU keys with TTL set

6. allkeys-random
- Evicts random keys

7. volatile-random
- Evicts random keys with TTL

8. volatile-ttl
- Evicts keys with shortest TTL first

## Check Current Policy

bash
# Connect to Redis
redis-cli -h my-redis.xxxxx.cache.amazonaws.com

# Check eviction policy
CONFIG GET maxmemory-policy

# Check memory usage
INFO memory


## Set Eviction Policy

### Via AWS Console
ElastiCache → Parameter Groups → Create/Modify → Set maxmemory-policy

### Via AWS CLI

bash
# Create custom parameter group
aws elasticache create-cache-parameter-group \
  --cache-parameter-group-name my-redis-params \
  --cache-parameter-group-family redis7 \
  --description "Custom Redis parameters"

# Modify eviction policy
aws elasticache modify-cache-parameter-group \
  --cache-parameter-group-name my-redis-params \
  --parameter-name-values \
    ParameterName=maxmemory-policy,ParameterValue=allkeys-lru

# Apply to cluster
aws elasticache modify-cache-cluster \
  --cache-cluster-id my-redis-cluster \
  --cache-parameter-group-name my-redis-params \
  --apply-immediately


## Monitor Memory Usage

bash
# CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ElastiCache \
  --metric-name DatabaseMemoryUsagePercentage \
  --dimensions Name=CacheClusterId,Value=my-redis-cluster \
  --start-time 2026-02-06T00:00:00Z \
  --end-time 2026-02-07T16:00:00Z \
  --period 3600 \
  --statistics Average


## Handle Full Memory in Application

javascript
const { createClient } = require('redis');

const redis = createClient({
  socket: {
    host: 'my-redis.xxxxx.cache.amazonaws.com',
    port: 6379
  }
});

redis.connect();

// Handle OOM errors gracefully
async function cacheData(key, value, ttl = 3600) {
  try {
    await redis.setEx(key, ttl, JSON.stringify(value));
    console.log('Data cached successfully');
  } catch (error) {
    if (error.message.includes('OOM') || error.message.includes('maxmemory')) {
      console.warn('Redis memory full, skipping cache');
      // Continue without caching - app still works
    } else {
      throw error;
    }
  }
}

// Always have fallback to database
async function getData(key) {
  try {
    const cached = await redis.get(key);
    if (cached) return JSON.parse(cached);
  } catch (error) {
    console.warn('Redis error, falling back to DB:', error.message);
  }
  
  // Fallback to database
  return await fetchFromDatabase(key);
}


## Solutions When Memory is Full

### 1. Increase Node Size

bash
# Scale up to larger node type
aws elasticache modify-cache-cluster \
  --cache-cluster-id my-redis-cluster \
  --cache-node-type cache.r7g.large \
  --apply-immediately


### 2. Add More Shards (Cluster Mode)

bash
# Add shards to cluster
aws elasticache increase-replica-count \
  --replication-group-id my-redis-cluster \
  --new-replica-count 3 \
  --apply-immediately


### 3. Reduce TTL

javascript
// Shorter TTL = faster eviction
await redis.setEx(key, 300, value); // 5 minutes instead of 1 hour


### 4. Set Eviction Policy

bash
# Use allkeys-lru for automatic eviction
maxmemory-policy = allkeys-lru


### 5. Clean Up Unused Keys

javascript
// Delete old/unused keys
await redis.del('old-key-1', 'old-key-2');

// Or use patterns
const keys = await redis.keys('temp:*');
if (keys.length > 0) {
  await redis.del(...keys);
}


## Best Practices

1. Set appropriate eviction policy:
allkeys-lru (most common)


2. Monitor memory usage:
Alert when > 80% full


3. Set TTL on all keys:
javascript
// Always set expiration
await redis.setEx(key, ttl, value);


4. Don't cache everything:
javascript
// Only cache frequently accessed data
if (accessCount > 10) {
  await cacheData(key, value);
}


5. Handle errors gracefully:
javascript
// App should work even if Redis fails
try {
  return await getFromCache(key);
} catch {
  return await getFromDatabase(key);
}


## CloudWatch Alarms

bash
# Alert when memory > 80%
aws cloudwatch put-metric-alarm \
  --alarm-name redis-high-memory \
  --metric-name DatabaseMemoryUsagePercentage \
  --namespace AWS/ElastiCache \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=CacheClusterId,Value=my-redis-cluster


## Summary

| Eviction Policy | Behavior When Full | Best For |
|----------------|-------------------|----------|
| noeviction | Returns errors | Never use in production |
| allkeys-lru | Auto-evicts old keys | General purpose (recommended) |
| volatile-lru | Evicts keys with TTL | When you control TTL |
| allkeys-lfu | Evicts rarely used | Frequency-based access |

Recommendation: Use allkeys-lru and monitor memory to stay under 80% usage.
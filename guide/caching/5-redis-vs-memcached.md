## ElastiCache: Redis vs Memcached

### Quick Comparison

| Feature | Redis | Memcached |
|---------|-------|-----------|
| Data Types | Strings, Lists, Sets, Hashes, Sorted Sets | Strings only |
| Persistence | Yes (snapshots, AOF) | No |
| Replication | Yes (Multi-AZ) | No |
| Transactions | Yes | No |
| Pub/Sub | Yes | No |
| Lua Scripts | Yes | No |
| Multi-threading | No (single-threaded) | Yes |
| Max Item Size | 512 MB | 1 MB |
| Backup/Restore | Yes | No |
| Sorting | Yes | No |
| Clustering | Yes | Yes |
| Complexity | More features | Simple |
| Use Case | Complex caching, sessions, queues | Simple key-value cache |

## Detailed Comparison

### Data Structures

Redis:
javascript
// Strings
await redis.set('key', 'value');

// Lists
await redis.lPush('mylist', 'item1', 'item2');

// Sets
await redis.sAdd('myset', 'member1', 'member2');

// Hashes
await redis.hSet('user:1', 'name', 'John', 'age', '30');

// Sorted Sets
await redis.zAdd('leaderboard', { score: 100, value: 'player1' });


Memcached:
javascript
// Only strings
await memcached.set('key', 'value');
await memcached.get('key');


### Persistence

Redis:
- Can save data to disk
- Survives restarts
- RDB snapshots or AOF logs

Memcached:
- In-memory only
- Data lost on restart
- No persistence

### Replication & High Availability

Redis:
bash
# Multi-AZ with automatic failover
aws elasticache create-replication-group \
  --replication-group-id my-redis \
  --replication-group-description "Redis cluster" \
  --engine redis \
  --cache-node-type cache.r7g.large \
  --num-cache-clusters 3 \
  --automatic-failover-enabled \
  --multi-az-enabled


Memcached:
bash
# No replication, just multiple nodes
aws elasticache create-cache-cluster \
  --cache-cluster-id my-memcached \
  --engine memcached \
  --cache-node-type cache.t3.medium \
  --num-cache-nodes 3


### Performance

Redis:
- Single-threaded per shard
- ~100K ops/sec per node
- Better for complex operations

Memcached:
- Multi-threaded
- ~200K+ ops/sec per node
- Better for simple get/set at scale

### Scaling

Redis:
bash
# Vertical: Upgrade node type
# Horizontal: Add shards (cluster mode)
aws elasticache modify-replication-group \
  --replication-group-id my-redis \
  --cache-node-type cache.r7g.xlarge


Memcached:
bash
# Horizontal: Add more nodes (easier)
aws elasticache modify-cache-cluster \
  --cache-cluster-id my-memcached \
  --num-cache-nodes 5


## Use Cases

### Use Redis When:

1. Complex Data Structures
javascript
// Leaderboard with sorted sets
await redis.zAdd('scores', { score: 1000, value: 'user1' });
await redis.zRevRange('scores', 0, 9); // Top 10


2. Session Storage
javascript
// Hash for user session
await redis.hSet('session:abc123', {
  userId: '123',
  username: 'john',
  loginTime: Date.now()
});
await redis.expire('session:abc123', 3600);


3. Pub/Sub Messaging
javascript
// Publisher
await redis.publish('notifications', 'New message');

// Subscriber
await redis.subscribe('notifications', (message) => {
  console.log(message);
});


4. Rate Limiting
javascript
// Increment counter with expiry
const count = await redis.incr(`rate:${userId}`);
if (count === 1) {
  await redis.expire(`rate:${userId}`, 60); // 1 minute window
}
if (count > 100) {
  throw new Error('Rate limit exceeded');
}


5. Queues
javascript
// Job queue with lists
await redis.lPush('jobs', JSON.stringify(job));
const job = await redis.brPop('jobs', 0); // Blocking pop


6. Need Persistence
- Data must survive restarts
- Backup/restore required

7. Need High Availability
- Multi-AZ failover
- Read replicas

### Use Memcached When:

1. Simple Key-Value Cache
javascript
// Just caching database queries
const key = `user:${userId}`;
let user = await memcached.get(key);

if (!user) {
  user = await db.query('SELECT * FROM users WHERE id = ?', [userId]);
  await memcached.set(key, user, 3600);
}


2. Large Cache Pools
- Need to scale horizontally easily
- Simple add/remove nodes

3. Multi-threaded Performance
- Very high throughput needed
- Simple operations

4. Distributed Caching
- Multiple app servers
- Consistent hashing

5. Cost Optimization
- Simpler = cheaper
- Less features = lower cost

6. Temporary Data Only
- Don't need persistence
- Data loss on restart is acceptable

## Code Examples

### Redis Implementation

javascript
const { createClient } = require('redis');

const redis = createClient({
  socket: { host: 'redis-endpoint', port: 6379 }
});

await redis.connect();

// Complex caching with data structures
async function cacheUserProfile(userId, profile) {
  // Store as hash
  await redis.hSet(`user:${userId}`, profile);
  await redis.expire(`user:${userId}`, 3600);
  
  // Add to active users set
  await redis.sAdd('active:users', userId);
  
  // Update leaderboard
  await redis.zAdd('user:scores', {
    score: profile.score,
    value: userId
  });
}


### Memcached Implementation

javascript
const Memcached = require('memcached');

const memcached = new Memcached('memcached-endpoint:11211');

// Simple caching
async function cacheData(key, value, ttl = 3600) {
  return new Promise((resolve, reject) => {
    memcached.set(key, value, ttl, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

async function getData(key) {
  return new Promise((resolve, reject) => {
    memcached.get(key, (err, data) => {
      if (err) reject(err);
      else resolve(data);
    });
  });
}


## Cost Comparison

Similar node types:
- cache.r7g.large (Redis): ~$0.188/hour
- cache.t3.medium (Memcached): ~$0.068/hour

Memcached is generally cheaper for equivalent memory

## Decision Matrix

| Requirement | Choose |
|-------------|--------|
| Simple key-value only | Memcached |
| Need lists, sets, hashes | Redis |
| Need persistence | Redis |
| Need pub/sub | Redis |
| Need transactions | Redis |
| Need highest throughput | Memcached |
| Need multi-threading | Memcached |
| Need replication/HA | Redis |
| Need backup/restore | Redis |
| Simplest solution | Memcached |
| Most features | Redis |

## Migration Consideration

Easy to switch:
- Both use similar key-value patterns
- Change client library
- Adjust for data structure differences

Recommendation:
- **Start with Redis** - More flexible, can do everything Memcached does
- **Use Memcached** only if you specifically need multi-threaded performance and don't need Redis features

Most common choice: Redis (90% of use cases)
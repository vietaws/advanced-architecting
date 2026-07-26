## Memcached Data Loss

### Single Node Failure

Memcached Cluster: 3 nodes
Node 1: Keys A, B, C
Node 2: Keys D, E, F  ← Goes down
Node 3: Keys G, H, I

Result: Keys D, E, F are LOST permanently


What happens:
- Data on failed node is gone
- No replication
- No automatic failover
- No recovery

### How Memcached Distributes Data

javascript
// Client uses consistent hashing
const Memcached = require('memcached');

const memcached = new Memcached([
  'node1:11211',
  'node2:11211',
  'node3:11211'
]);

// Key 'user:123' goes to node2
await memcached.set('user:123', data);

// If node2 fails:
// - Data is lost
// - Next request will be cache MISS
// - App fetches from database
// - Caches to different node (node1 or node3)


## Redis vs Memcached HA

### Memcached (No HA)

Primary Cluster:
├── Node 1 (data: A, B, C)
├── Node 2 (data: D, E, F)  ← Fails
└── Node 3 (data: G, H, I)

After failure:
├── Node 1 (data: A, B, C)
└── Node 3 (data: G, H, I)

Lost: D, E, F (no recovery)


### Redis (With HA)

Replication Group:
├── Primary (data: A-Z)
├── Replica 1 (data: A-Z)  ← Automatic failover
└── Replica 2 (data: A-Z)

Primary fails:
├── Replica 1 → Promoted to Primary (data: A-Z)
└── Replica 2 (data: A-Z)

Lost: Nothing (data preserved)


## Impact on Your Application

### Memcached Node Failure

javascript
const memcached = new Memcached(['node1:11211', 'node2:11211']);

// Before node2 fails
await memcached.set('user:123', userData); // Stored on node2

// Node2 goes down

// Next request
const user = await memcached.get('user:123'); // Returns null (cache MISS)

// App must handle
if (!user) {
  user = await database.query('SELECT * FROM users WHERE id = 123');
  await memcached.set('user:123', user); // Now cached on node1 or node3
}


Result:
- More database queries
- Slower response times
- But app still works (if coded properly)

### Redis Node Failure (with replication)

javascript
const redis = createClient({
  socket: { host: 'redis-cluster-endpoint', port: 6379 }
});

// Data stored on primary
await redis.set('user:123', userData);

// Primary fails → Replica promoted automatically

// Next request
const user = await redis.get('user:123'); // Still returns data ✓

// No cache miss, no database query needed


## Memcached Best Practices

Since data can be lost, always:

javascript
// 1. Always have fallback to database
async function getUser(userId) {
  // Try cache
  let user = await memcached.get(`user:${userId}`);
  
  // Fallback to DB if not in cache
  if (!user) {
    user = await db.query('SELECT * FROM users WHERE id = ?', [userId]);
    await memcached.set(`user:${userId}`, user, 3600);
  }
  
  return user;
}

// 2. Handle Memcached failures gracefully
async function cacheData(key, value) {
  try {
    await memcached.set(key, value, 3600);
  } catch (error) {
    console.warn('Memcached unavailable, continuing without cache');
    // App continues to work
  }
}

// 3. Don't store critical data in Memcached
// ❌ Don't do this:
await memcached.set('order:payment:status', 'completed'); // Could be lost!

// ✓ Do this:
await database.save({ orderId, status: 'completed' }); // Persistent
await memcached.set('order:123', orderData, 300); // Just for caching


## Summary

| Scenario | Memcached | Redis (with replication) |
|----------|-----------|--------------------------|
| Node fails | Data lost | Data preserved |
| Automatic failover | No | Yes |
| Data recovery | No | Yes |
| High Availability | No | Yes |
| Use case | Cache only | Cache + persistence |

Key takeaway:
- **Memcached** = Cache only, data loss is acceptable
- **Redis** = Can be cache + persistent storage with HA

Your understanding is 100% correct. Memcached has no HA, and data is lost when a node fails.
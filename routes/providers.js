const express = require('express');
const pool = require('../db/postgres');
const router = express.Router();

router.post('/', async (req, res) => {
  try {
    const { name, city } = req.body;
    
    if (!name) {
      return res.status(400).json({ error: 'name is required' });
    }

    console.log('Creating provider:', { name, city });
    
    const result = await pool.query(
      'INSERT INTO providers (name, city) VALUES ($1, $2) RETURNING id',
      [name, city || null]
    );
    
    res.json({ message: 'Provider created', id: result.rows[0].id });
  } catch (error) {
    console.error('Provider creation error:', error);
    res.status(500).json({ error: error.message, detail: error.detail });
  }
});

router.get('/', async (req, res) => {
  try {
    console.log('Fetching all providers...');
    const startTime = Date.now();
    
    // Force fresh query - no prepared statement caching
    const result = await pool.query('SELECT * FROM providers ORDER BY id');
    
    const responseTime = Date.now() - startTime;
    console.log(`Found ${result.rows.length} providers in ${responseTime}ms`);
    
    const providers = result.rows.map(row => ({
      ...row,
      responseTime: responseTime
    }));
    
    console.log('Sample provider with responseTime:', providers[0]);
    
    // Disable HTTP caching
    res.set({
      'Cache-Control': 'no-store, no-cache, must-revalidate, private',
      'Pragma': 'no-cache',
      'Expires': '0'
    });
    
    res.json(providers);
  } catch (error) {
    console.error('Provider fetch error:', error);
    res.status(500).json({ error: error.message });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM providers WHERE id = $1', [req.params.id]);
    res.json(result.rows[0] || {});
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const { name, city } = req.body;
    await pool.query(
      'UPDATE providers SET name = $1, city = $2 WHERE id = $3',
      [name, city, req.params.id]
    );
    res.json({ message: 'Provider updated' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM providers WHERE id = $1', [req.params.id]);
    res.json({ message: 'Provider deleted' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;

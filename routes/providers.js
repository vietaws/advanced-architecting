import express from 'express';
import pool from '../db/postgres.js';
import logger from '../logger.js';

const router = express.Router();

router.post('/', async (req, res) => {
  try {
    const { name, city } = req.body;

    if (!name) {
      return res.status(400).json({ error: 'name is required' });
    }

    const result = await pool.query(
      'INSERT INTO providers (name, city) VALUES ($1, $2) RETURNING id',
      [name, city || null]
    );

    const id = result.rows[0].id;
    logger.info({ action: 'provider.create', id, name, city }, 'Provider created');

    res.json({ message: 'Provider created', id });
  } catch (error) {
    logger.error({ action: 'provider.create', error: error.message }, 'Failed to create provider');
    res.status(500).json({ error: error.message, detail: error.detail });
  }
});

router.get('/', async (req, res) => {
  try {
    const startTime = Date.now();
    const result = await pool.query('SELECT * FROM providers ORDER BY id');
    const responseTime = Date.now() - startTime;

    const providers = result.rows.map(row => ({ ...row, responseTime }));

    res.set({
      'Cache-Control': 'no-store, no-cache, must-revalidate, private',
      'Pragma': 'no-cache',
      'Expires': '0'
    });

    res.json(providers);
  } catch (error) {
    logger.error({ action: 'provider.list', error: error.message }, 'Failed to fetch providers');
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

    logger.info({ action: 'provider.update', id: req.params.id, name, city }, 'Provider updated');

    res.json({ message: 'Provider updated' });
  } catch (error) {
    logger.error({ action: 'provider.update', id: req.params.id, error: error.message }, 'Failed to update provider');
    res.status(500).json({ error: error.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM providers WHERE id = $1', [req.params.id]);

    logger.info({ action: 'provider.delete', id: req.params.id }, 'Provider deleted');

    res.json({ message: 'Provider deleted' });
  } catch (error) {
    logger.error({ action: 'provider.delete', id: req.params.id, error: error.message }, 'Failed to delete provider');
    res.status(500).json({ error: error.message });
  }
});

export default router;

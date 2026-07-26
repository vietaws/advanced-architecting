import express from 'express';
import multer from 'multer';
import { promises as fs } from 'fs';
import { existsSync } from 'fs';
import { extname, join } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import pool from '../db/postgres.js';
import logger from '../logger.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const router = express.Router();

const EFS_MOUNT_POINT = '/data/efs';
const FALLBACK_DIR = join(__dirname, '../uploads');
const upload = multer({ dest: '/tmp/' });

async function ensureStorageDir() {
  try {
    await fs.access(EFS_MOUNT_POINT);
    return EFS_MOUNT_POINT;
  } catch {
    if (!existsSync(FALLBACK_DIR)) {
      await fs.mkdir(FALLBACK_DIR, { recursive: true });
    }
    return FALLBACK_DIR;
  }
}

async function saveImageToEFS(file) {
  const storageDir = await ensureStorageDir();
  const ext = extname(file.originalname);
  const filename = `provider-${Date.now()}-${Math.random().toString(36).substring(7)}${ext}`;
  const destPath = join(storageDir, filename);
  await fs.copyFile(file.path, destPath);
  await fs.unlink(file.path);
  return filename;
}

async function deleteImageFromEFS(filename) {
  if (!filename) return;
  try {
    const storageDir = await ensureStorageDir();
    await fs.unlink(join(storageDir, filename));
  } catch (err) {
    // File may not exist — log and continue
    logger.warn({ action: 'provider.image_delete', filename, error: err.message }, 'Could not delete provider image from EFS');
  }
}

// Auto-migrate: add image_filename column if it doesn't exist
async function ensureImageColumn() {
  try {
    await pool.query(`
      ALTER TABLE providers ADD COLUMN IF NOT EXISTS image_filename VARCHAR(255)
    `);
  } catch (err) {
    logger.warn({ action: 'provider.migrate', error: err.message }, 'Migration warning');
  }
}

ensureImageColumn();

router.post('/', upload.single('image'), async (req, res) => {
  try {
    const { name, city } = req.body;

    if (!name) {
      return res.status(400).json({ error: 'name is required' });
    }

    let image_filename = null;
    if (req.file) {
      image_filename = await saveImageToEFS(req.file);
    }

    const startTime = Date.now();
    const result = await pool.query(
      'INSERT INTO providers (name, city, image_filename) VALUES ($1, $2, $3) RETURNING id',
      [name, city || null, image_filename]
    );
    const latency_ms = Date.now() - startTime;

    const id = result.rows[0].id;
    const image_url = image_filename ? `/providers/image/${image_filename}` : null;

    logger.info({ action: 'provider.create', source: 'rds', id, name, city, has_image: !!image_filename, latency_ms }, 'Provider created');

    res.json({ message: 'Provider created', id, image_url });
  } catch (error) {
    if (req.file?.path) {
      try { await fs.unlink(req.file.path); } catch {}
    }
    logger.error({ action: 'provider.create', error: error.message }, 'Failed to create provider');
    res.status(500).json({ error: error.message, detail: error.detail });
  }
});

router.get('/', async (req, res) => {
  try {
    const startTime = Date.now();
    const result = await pool.query('SELECT * FROM providers ORDER BY id');
    const latency_ms = Date.now() - startTime;

    logger.info({ action: 'provider.list', source: 'rds', count: result.rows.length, latency_ms }, 'RDS query');

    const providers = result.rows.map(row => ({
      ...row,
      image_url: row.image_filename ? `/providers/image/${row.image_filename}` : null,
      responseTime: latency_ms
    }));

    res.set({
      'Cache-Control': 'no-store, no-cache, must-revalidate, private',
      'Pragma': 'no-cache',
      'Expires': '0'
    });

    res.json(providers);
  } catch (error) {
    logger.error({ action: 'provider.list', source: 'rds', error: error.message }, 'Failed to fetch providers');
    res.status(500).json({ error: error.message });
  }
});

router.get('/image/:filename', async (req, res) => {
  try {
    const storageDir = await ensureStorageDir();
    const filePath = join(storageDir, req.params.filename);
    await fs.access(filePath);
    res.sendFile(filePath);
  } catch (error) {
    logger.error({ action: 'provider.image_serve', filename: req.params.filename, error: error.message }, 'Provider image not found');
    res.status(404).json({ error: 'Image not found' });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const startTime = Date.now();
    const result = await pool.query('SELECT * FROM providers WHERE id = $1', [req.params.id]);
    const latency_ms = Date.now() - startTime;

    logger.info({ action: 'provider.get', source: 'rds', id: req.params.id, found: !!result.rows[0], latency_ms }, 'RDS query');

    if (!result.rows[0]) return res.json({});

    const row = result.rows[0];
    res.json({
      ...row,
      image_url: row.image_filename ? `/providers/image/${row.image_filename}` : null
    });
  } catch (error) {
    logger.error({ action: 'provider.get', source: 'rds', id: req.params.id, error: error.message }, 'Failed to get provider');
    res.status(500).json({ error: error.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const { name, city } = req.body;
    const startTime = Date.now();
    await pool.query(
      'UPDATE providers SET name = $1, city = $2 WHERE id = $3',
      [name, city, req.params.id]
    );
    const latency_ms = Date.now() - startTime;

    logger.info({ action: 'provider.update', source: 'rds', id: req.params.id, name, city, latency_ms }, 'Provider updated');

    res.json({ message: 'Provider updated' });
  } catch (error) {
    logger.error({ action: 'provider.update', id: req.params.id, error: error.message }, 'Failed to update provider');
    res.status(500).json({ error: error.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    // Fetch image_filename first so we can delete it from EFS
    const existing = await pool.query('SELECT image_filename FROM providers WHERE id = $1', [req.params.id]);
    const image_filename = existing.rows[0]?.image_filename;

    const startTime = Date.now();
    await pool.query('DELETE FROM providers WHERE id = $1', [req.params.id]);
    const latency_ms = Date.now() - startTime;

    // Delete image from EFS after DB record is gone
    await deleteImageFromEFS(image_filename);

    logger.info({ action: 'provider.delete', source: 'rds', id: req.params.id, latency_ms }, 'Provider deleted');

    res.json({ message: 'Provider deleted' });
  } catch (error) {
    logger.error({ action: 'provider.delete', id: req.params.id, error: error.message }, 'Failed to delete provider');
    res.status(500).json({ error: error.message });
  }
});

export default router;

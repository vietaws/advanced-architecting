import express from 'express';
import multer from 'multer';
import { promises as fs } from 'fs';
import { existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join, extname } from 'path';
import logger from '../logger.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const router = express.Router();

const EFS_MOUNT_POINT = '/data/efs';
const FALLBACK_DIR = join(__dirname, '../uploads');

// Multer stores upload in /tmp first; we then copy to EFS / fallback
const upload = multer({ dest: '/tmp/' });

/**
 * Resolve the active storage directory.
 * Uses EFS mount when available, falls back to a local uploads dir.
 */
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

// ── GET / — list all images ───────────────────────────────────────────────────
router.get('/', async (req, res) => {
  try {
    const storageDir = await ensureStorageDir();
    const files = await fs.readdir(storageDir);
    const imageFiles = files.filter(file => /\.(jpg|jpeg|png|gif|webp)$/i.test(file));

    const imagesWithStats = await Promise.all(
      imageFiles.map(async (file) => {
        try {
          const stats = await fs.stat(join(storageDir, file));
          return { name: file, url: `/efs/image/${file}`, uploadDate: stats.mtime };
        } catch {
          return { name: file, url: `/efs/image/${file}`, uploadDate: null };
        }
      })
    );

    res.json(
      imagesWithStats.sort((a, b) => new Date(b.uploadDate) - new Date(a.uploadDate))
    );
  } catch (error) {
    logger.error({ action: 'efs.list', error: error.message }, 'Failed to list EFS images');
    res.status(500).json({ error: error.message });
  }
});

// ── POST /upload — upload an image to EFS ────────────────────────────────────
router.post('/upload', upload.single('image'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }

    const storageDir = await ensureStorageDir();
    const ext = extname(req.file.originalname);
    const filename = `${Date.now()}-${Math.random().toString(36).substring(7)}${ext}`;
    const destPath = join(storageDir, filename);

    await fs.copyFile(req.file.path, destPath);
    await fs.unlink(req.file.path);

    logger.info(
      {
        action: 'efs.upload',
        filename,
        original: req.file.originalname,
        size: req.file.size,
        storage: storageDir,
      },
      'Image uploaded to EFS'
    );

    res.json({ message: 'Image uploaded successfully', filename, url: `/efs/image/${filename}` });
  } catch (error) {
    logger.error(
      { action: 'efs.upload', original: req.file?.originalname, error: error.message },
      'Failed to upload image to EFS'
    );
    if (req.file?.path) {
      try { await fs.unlink(req.file.path); } catch { /* ignore */ }
    }
    res.status(500).json({ error: error.message });
  }
});

// ── GET /image/:filename — serve image from EFS ───────────────────────────────
router.get('/image/:filename', async (req, res) => {
  try {
    const storageDir = await ensureStorageDir();
    const filePath = join(storageDir, req.params.filename);
    await fs.access(filePath);
    res.sendFile(filePath);
  } catch (error) {
    logger.error(
      { action: 'efs.serve', filename: req.params.filename, error: error.message },
      'Image not found'
    );
    res.status(404).json({ error: 'Image not found' });
  }
});

// ── DELETE /:filename — delete image from EFS ────────────────────────────────
router.delete('/:filename', async (req, res) => {
  try {
    const storageDir = await ensureStorageDir();
    const filePath = join(storageDir, req.params.filename);
    await fs.unlink(filePath);

    logger.info({ action: 'efs.delete', filename: req.params.filename }, 'Image deleted from EFS');

    res.json({ message: 'Image deleted successfully' });
  } catch (error) {
    logger.error(
      { action: 'efs.delete', filename: req.params.filename, error: error.message },
      'Failed to delete image from EFS'
    );
    res.status(error.code === 'ENOENT' ? 404 : 500).json({ error: error.message });
  }
});

export default router;

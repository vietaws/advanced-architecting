import express from 'express';
import multer from 'multer';
import { promises as fs } from 'fs';
import { existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join, extname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const router = express.Router();

const EFS_MOUNT_POINT = '/data/efs';
const FALLBACK_DIR = join(__dirname, '../uploads');
const upload = multer({ dest: '/tmp/' });

async function ensureStorageDir() {
  try {
    await fs.access(EFS_MOUNT_POINT);
    console.log('Using EFS mount point:', EFS_MOUNT_POINT);
    return EFS_MOUNT_POINT;
  } catch {
    console.log('EFS not mounted, using fallback directory:', FALLBACK_DIR);
    if (!existsSync(FALLBACK_DIR)) {
      await fs.mkdir(FALLBACK_DIR, { recursive: true });
    }
    return FALLBACK_DIR;
  }
}

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

    res.json(imagesWithStats.sort((a, b) => new Date(b.uploadDate) - new Date(a.uploadDate)));
  } catch (error) {
    console.error('Error reading images:', error);
    res.status(500).json({ error: error.message });
  }
});

router.post('/upload', upload.single('image'), async (req, res) => {
  try {
    console.log('Upload request received:', req.file);

    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }

    const storageDir = await ensureStorageDir();
    const ext = extname(req.file.originalname);
    const filename = `${Date.now()}-${Math.random().toString(36).substring(7)}${ext}`;
    const destPath = join(storageDir, filename);

    console.log('Moving file from', req.file.path, 'to', destPath);

    await fs.copyFile(req.file.path, destPath);
    await fs.unlink(req.file.path);

    console.log('File uploaded successfully:', filename);
    res.json({ message: 'Image uploaded successfully', filename, url: `/efs/image/${filename}` });
  } catch (error) {
    console.error('Error uploading image:', error);
    if (req.file?.path) {
      try { await fs.unlink(req.file.path); } catch {}
    }
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
    console.error('Error serving image:', error);
    res.status(404).json({ error: 'Image not found' });
  }
});

router.delete('/:filename', async (req, res) => {
  try {
    const storageDir = await ensureStorageDir();
    const filePath = join(storageDir, req.params.filename);
    await fs.unlink(filePath);
    res.json({ message: 'Image deleted successfully' });
  } catch (error) {
    console.error('Error deleting image:', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;

'use strict';

const express = require('express');
const multer  = require('multer');
const path    = require('path');
const fs      = require('fs');

// Set umask to 0 so files written to NFS/SMB are world-writable (rw-rw-rw-)
// This allows any user (nobody, webapp, etc.) to delete files regardless of who created them
process.umask(0o000);

// ---------------------------------------------------------------------------
// Config from .env / environment variables
// ---------------------------------------------------------------------------
const PORT       = process.env.PORT       || 80;
const NFS_MOUNT  = process.env.NFS_MOUNT  || '/mnt/nfs';
const SMB_MOUNT  = process.env.SMB_MOUNT  || '/mnt/smb';

const ALLOWED_EXT = new Set(['.jpg', '.jpeg', '.png', '.gif']);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function isAllowedExt(filename) {
  return ALLOWED_EXT.has(path.extname(filename).toLowerCase());
}

function formatBytes(bytes) {
  if (!bytes) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

function listImages(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter(f => isAllowedExt(f))
    .map(f => {
      const stat = fs.statSync(path.join(dir, f));
      return { filename: f, size: formatBytes(stat.size), sizeRaw: stat.size };
    });
}

// ---------------------------------------------------------------------------
// Multer — disk storage for both NFS and SMB
// ---------------------------------------------------------------------------
function diskUploader(mountPath) {
  return multer({
    storage: multer.diskStorage({
      destination: (req, file, cb) => {
        fs.mkdirSync(mountPath, { recursive: true });
        cb(null, mountPath);
      },
      filename: (req, file, cb) => cb(null, file.originalname),
    }),
    fileFilter: (req, file, cb) =>
      isAllowedExt(file.originalname)
        ? cb(null, true)
        : cb(new Error('Only JPG, PNG and GIF files are allowed')),
    limits: { fileSize: 20 * 1024 * 1024 },
  });
}

// ---------------------------------------------------------------------------
// Express app
// ---------------------------------------------------------------------------
const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// ---------------------------------------------------------------------------
// Generic route factory — keeps NFS and SMB routes DRY
// ---------------------------------------------------------------------------
function mountRoutes(router, mountPath, label) {
  // List images
  router.get('/images', (req, res) => {
    try {
      res.json({ items: listImages(mountPath) });
    } catch (err) {
      console.error(`${label} list error:`, err);
      res.status(500).json({ error: err.message });
    }
  });

  // Serve individual image file
  router.get('/images/:filename', (req, res) => {
    const filename = path.basename(req.params.filename);
    if (!isAllowedExt(filename)) return res.status(400).json({ error: 'File type not allowed' });
    const filepath = path.join(mountPath, filename);
    if (!fs.existsSync(filepath)) return res.status(404).json({ error: 'Not found' });
    res.sendFile(filepath, { root: '/' }, (err) => {
      if (err) {
        console.error(`${label} serve error:`, err);
        res.status(500).json({ error: err.message });
      }
    });
  });

  // Upload image
  router.post('/images', (req, res) => {
    diskUploader(mountPath).single('image')(req, res, (err) => {
      if (err) {
        console.error(`${label} upload error:`, err);
        return res.status(400).json({ error: err.message });
      }
      if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
      res.json({ message: 'Uploaded', filename: req.file.filename });
    });
  });

  // Delete image
  router.delete('/images', (req, res) => {
    console.log(`${label} DELETE req.body:`, JSON.stringify(req.body));
    const filename = path.basename(req.body.filename || '');
    console.log(`${label} DELETE filename resolved:`, filename);
    if (!filename) return res.status(400).json({ error: 'filename is required' });
    const filepath = path.join(mountPath, filename);
    console.log(`${label} DELETE filepath:`, filepath, 'exists:', fs.existsSync(filepath));
    if (!fs.existsSync(filepath)) return res.status(404).json({ error: 'Not found' });
    try {
      fs.unlinkSync(filepath);
      res.json({ message: 'Deleted', filename });
    } catch (err) {
      console.error(`${label} delete error:`, err);
      res.status(500).json({ error: err.message });
    }
  });
}

const nfsRouter = express.Router();
const smbRouter = express.Router();
mountRoutes(nfsRouter, NFS_MOUNT, 'NFS');
mountRoutes(smbRouter, SMB_MOUNT, 'SMB');

app.use('/api/nfs', nfsRouter);
app.use('/api/smb', smbRouter);

// ---------------------------------------------------------------------------
// Global error handler — ensures all errors return JSON, never HTML
// ---------------------------------------------------------------------------
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
app.listen(PORT, () => {
  console.log(`OP Demo app running on port ${PORT}`);
  console.log(`  NFS mount : ${NFS_MOUNT}`);
  console.log(`  SMB mount : ${SMB_MOUNT}`);
});

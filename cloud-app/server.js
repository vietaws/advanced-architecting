'use strict';

const express = require('express');
const multer  = require('multer');
const path    = require('path');
const fs      = require('fs');

const {
  S3Client,
  ListObjectsV2Command,
  PutObjectCommand,
  DeleteObjectCommand,
  GetObjectCommand,
} = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');

// ---------------------------------------------------------------------------
// Config from environment variables (set in userdata / systemd unit)
// ---------------------------------------------------------------------------
const PORT        = process.env.PORT        || 80;
const REGION      = process.env.AWS_REGION  || 'us-east-1';
const S3_BUCKET   = process.env.S3_BUCKET;          // required
const S3_PREFIX   = process.env.S3_PREFIX   || 'images/products/';
const EFS_MOUNT   = process.env.EFS_MOUNT   || '/mnt/efs';
const EFS_SUBDIR  = process.env.EFS_SUBDIR  || 'images/products';

const ALLOWED_EXT = new Set(['.jpg', '.jpeg', '.png', '.gif']);
const PRESIGN_TTL = 300; // seconds

if (!S3_BUCKET) {
  console.error('ERROR: S3_BUCKET environment variable is required');
  process.exit(1);
}

// ---------------------------------------------------------------------------
// AWS SDK
// ---------------------------------------------------------------------------
const s3 = new S3Client({ region: REGION });

// ---------------------------------------------------------------------------
// EFS helpers
// ---------------------------------------------------------------------------
function efsDir() {
  return path.join(EFS_MOUNT, EFS_SUBDIR);
}

function ensureEfsDir() {
  const dir = efsDir();
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function isAllowedExt(filename) {
  return ALLOWED_EXT.has(path.extname(filename).toLowerCase());
}

function formatBytes(bytes) {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

// ---------------------------------------------------------------------------
// Multer: memory storage for S3 uploads, disk storage for EFS uploads
// ---------------------------------------------------------------------------
const memStorage  = multer.memoryStorage();
const diskStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    ensureEfsDir();
    cb(null, efsDir());
  },
  filename: (req, file, cb) => cb(null, file.originalname),
});

function imageFilter(req, file, cb) {
  if (isAllowedExt(file.originalname)) return cb(null, true);
  cb(new Error('Only JPG, PNG and GIF files are allowed'));
}

const uploadToMem  = multer({ storage: memStorage,  fileFilter: imageFilter, limits: { fileSize: 20 * 1024 * 1024 } });
const uploadToDisk = multer({ storage: diskStorage, fileFilter: imageFilter, limits: { fileSize: 20 * 1024 * 1024 } });

// ---------------------------------------------------------------------------
// Express app
// ---------------------------------------------------------------------------
const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// ---------------------------------------------------------------------------
// S3 routes
// ---------------------------------------------------------------------------

// List images in S3
app.get('/api/s3/images', async (req, res) => {
  try {
    const cmd = new ListObjectsV2Command({
      Bucket: S3_BUCKET,
      Prefix: S3_PREFIX,
    });
    const data = await s3.send(cmd);

    const items = await Promise.all(
      (data.Contents || [])
        .filter(obj => isAllowedExt(obj.Key))
        .map(async obj => {
          const filename = path.basename(obj.Key);
          const url = await getSignedUrl(
            s3,
            new GetObjectCommand({ Bucket: S3_BUCKET, Key: obj.Key }),
            { expiresIn: PRESIGN_TTL }
          );
          return {
            key:      obj.Key,
            filename,
            size:     formatBytes(obj.Size),
            sizeRaw:  obj.Size,
            url,
          };
        })
    );

    res.json({ items });
  } catch (err) {
    console.error('S3 list error:', err);
    res.status(500).json({ error: err.message });
  }
});

// Upload image to S3
app.post('/api/s3/images', (req, res) => {
  uploadToMem.single('image')(req, res, async (err) => {
    if (err) {
      console.error('S3 multer error:', err);
      return res.status(400).json({ error: err.message });
    }
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
    const key = S3_PREFIX + req.file.originalname;
    try {
      await s3.send(new PutObjectCommand({
        Bucket:      S3_BUCKET,
        Key:         key,
        Body:        req.file.buffer,
        ContentType: req.file.mimetype,
      }));
      res.json({ message: 'Uploaded', key });
    } catch (err) {
      console.error('S3 upload error:', err);
      res.status(500).json({ error: err.message });
    }
  });
});

// Delete image from S3
app.delete('/api/s3/images', async (req, res) => {
  const { key } = req.body;
  if (!key) return res.status(400).json({ error: 'key is required' });
  // Safety: only allow deletion within the configured prefix
  if (!key.startsWith(S3_PREFIX)) {
    return res.status(403).json({ error: 'Key outside allowed prefix' });
  }
  try {
    await s3.send(new DeleteObjectCommand({ Bucket: S3_BUCKET, Key: key }));
    res.json({ message: 'Deleted', key });
  } catch (err) {
    console.error('S3 delete error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ---------------------------------------------------------------------------
// EFS routes
// ---------------------------------------------------------------------------

// List images from EFS
app.get('/api/efs/images', (req, res) => {
  try {
    ensureEfsDir();
    const dir = efsDir();
    const files = fs.readdirSync(dir).filter(f => isAllowedExt(f));
    const items = files.map(filename => {
      const stat = fs.statSync(path.join(dir, filename));
      return {
        filename,
        size:    formatBytes(stat.size),
        sizeRaw: stat.size,
      };
    });
    res.json({ items });
  } catch (err) {
    console.error('EFS list error:', err);
    res.status(500).json({ error: err.message });
  }
});

// Serve individual EFS image file
app.get('/api/efs/images/:filename', (req, res) => {
  const filename = path.basename(req.params.filename); // prevent path traversal
  if (!isAllowedExt(filename)) return res.status(400).json({ error: 'File type not allowed' });
  const filepath = path.join(efsDir(), filename);
  if (!fs.existsSync(filepath)) return res.status(404).json({ error: 'Not found' });
  res.sendFile(filepath, { root: '/' }, (err) => {
    if (err) {
      console.error('EFS serve error:', err);
      res.status(500).json({ error: err.message });
    }
  });
});

// Upload image to EFS
app.post('/api/efs/images', (req, res) => {
  uploadToDisk.single('image')(req, res, (err) => {
    if (err) {
      console.error('EFS multer error:', err);
      return res.status(400).json({ error: err.message });
    }
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
    res.json({ message: 'Uploaded', filename: req.file.filename });
  });
});

// Delete image from EFS
app.delete('/api/efs/images', (req, res) => {
  const { filename } = req.body;
  if (!filename) return res.status(400).json({ error: 'filename is required' });
  const safe = path.basename(filename); // prevent path traversal
  const filepath = path.join(efsDir(), safe);
  if (!fs.existsSync(filepath)) return res.status(404).json({ error: 'Not found' });
  try {
    fs.unlinkSync(filepath);
    res.json({ message: 'Deleted', filename: safe });
  } catch (err) {
    console.error('EFS delete error:', err);
    res.status(500).json({ error: err.message });
  }
});

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
  console.log(`Demo app running on port ${PORT}`);
  console.log(`  S3 bucket : ${S3_BUCKET}`);
  console.log(`  S3 prefix : ${S3_PREFIX}`);
  console.log(`  EFS path  : ${efsDir()}`);
});

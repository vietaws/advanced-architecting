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
// Config from environment variables (set via .env / systemd EnvironmentFile)
// ---------------------------------------------------------------------------
const PORT         = process.env.PORT          || 80;
const REGION       = process.env.AWS_REGION    || 'us-east-1';
const S3_BUCKET    = process.env.S3_BUCKET;             // required
const S3_PREFIX    = process.env.S3_PREFIX     || 'images/';
const STORAGE_MODE = process.env.STORAGE_MODE  || 'efs'; // 'efs' or 'ebs'
const LOCAL_MOUNT  = process.env.LOCAL_MOUNT   || '/mnt/efs';
const LOCAL_SUBDIR = process.env.LOCAL_SUBDIR  || 'images/products';

const ALLOWED_EXT = new Set(['.jpg', '.jpeg', '.png', '.gif']);
const PRESIGN_TTL = 300; // seconds

const TAB_LABELS = {
  efs: 'Amazon EFS',
  ebs: 'Amazon EBS',
};

if (!S3_BUCKET) {
  console.error('ERROR: S3_BUCKET environment variable is required');
  process.exit(1);
}

// ---------------------------------------------------------------------------
// AWS SDK
// ---------------------------------------------------------------------------
const s3 = new S3Client({ region: REGION });

// ---------------------------------------------------------------------------
// Local storage helpers (works for both EFS and EBS mounts)
// ---------------------------------------------------------------------------
function localDir() {
  return path.join(LOCAL_MOUNT, LOCAL_SUBDIR);
}

function ensureLocalDir() {
  const dir = localDir();
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
// Multer: memory storage for S3, disk storage for local (EFS/EBS)
// ---------------------------------------------------------------------------
const memStorage  = multer.memoryStorage();
const diskStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    ensureLocalDir();
    cb(null, localDir());
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
// Config endpoint — frontend reads this to set dynamic tab label
// ---------------------------------------------------------------------------
app.get('/api/config', (req, res) => {
  res.json({
    storageMode: STORAGE_MODE,
    tabLabel:    TAB_LABELS[STORAGE_MODE] || STORAGE_MODE.toUpperCase(),
  });
});

// ---------------------------------------------------------------------------
// S3 routes
// ---------------------------------------------------------------------------
app.get('/api/s3/images', async (req, res) => {
  try {
    const data = await s3.send(new ListObjectsV2Command({
      Bucket: S3_BUCKET,
      Prefix: S3_PREFIX,
    }));
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
          return { key: obj.Key, filename, size: formatBytes(obj.Size), sizeRaw: obj.Size, url };
        })
    );
    res.json({ items });
  } catch (err) {
    console.error('S3 list error:', err);
    res.status(500).json({ error: err.message });
  }
});

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

app.delete('/api/s3/images', async (req, res) => {
  const { key } = req.body;
  if (!key) return res.status(400).json({ error: 'key is required' });
  if (!key.startsWith(S3_PREFIX)) return res.status(403).json({ error: 'Key outside allowed prefix' });
  try {
    await s3.send(new DeleteObjectCommand({ Bucket: S3_BUCKET, Key: key }));
    res.json({ message: 'Deleted', key });
  } catch (err) {
    console.error('S3 delete error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ---------------------------------------------------------------------------
// Local storage routes — /api/local/* (works for both EFS and EBS)
// ---------------------------------------------------------------------------
app.get('/api/local/images', (req, res) => {
  try {
    ensureLocalDir();
    const dir   = localDir();
    const files = fs.readdirSync(dir).filter(f => isAllowedExt(f));
    const items = files.map(filename => {
      const stat = fs.statSync(path.join(dir, filename));
      return { filename, size: formatBytes(stat.size), sizeRaw: stat.size };
    });
    res.json({ items });
  } catch (err) {
    console.error('Local list error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/local/images/:filename', (req, res) => {
  const filename = path.basename(req.params.filename);
  if (!isAllowedExt(filename)) return res.status(400).json({ error: 'File type not allowed' });
  const filepath = path.join(localDir(), filename);
  if (!fs.existsSync(filepath)) return res.status(404).json({ error: 'Not found' });
  res.sendFile(filepath, { root: '/' }, (err) => {
    if (err) {
      console.error('Local serve error:', err);
      res.status(500).json({ error: err.message });
    }
  });
});

app.post('/api/local/images', (req, res) => {
  uploadToDisk.single('image')(req, res, (err) => {
    if (err) {
      console.error('Local multer error:', err);
      return res.status(400).json({ error: err.message });
    }
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
    res.json({ message: 'Uploaded', filename: req.file.filename });
  });
});

app.delete('/api/local/images', (req, res) => {
  const { filename } = req.body;
  if (!filename) return res.status(400).json({ error: 'filename is required' });
  const safe     = path.basename(filename);
  const filepath = path.join(localDir(), safe);
  if (!fs.existsSync(filepath)) return res.status(404).json({ error: 'Not found' });
  try {
    fs.unlinkSync(filepath);
    res.json({ message: 'Deleted', filename: safe });
  } catch (err) {
    console.error('Local delete error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ---------------------------------------------------------------------------
// Global error handler
// ---------------------------------------------------------------------------
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
app.listen(PORT, () => {
  console.log(`Cloud Demo app running on port ${PORT}`);
  console.log(`  S3 bucket    : ${S3_BUCKET}`);
  console.log(`  S3 prefix    : ${S3_PREFIX}`);
  console.log(`  Storage mode : ${STORAGE_MODE} (${TAB_LABELS[STORAGE_MODE] || STORAGE_MODE})`);
  console.log(`  Local path   : ${localDir()}`);
});

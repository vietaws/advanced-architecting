import express from 'express';
import { promises as fs, constants as fsConstants } from 'fs';
import logger from './logger.js';
import providerRoutes from './routes/providers.js';
import efsRoutes from './routes/efs.js';
import pool from './db/postgres.js';

const app = express();
const PORT = process.env.PORT || 3002;
const EFS_MOUNT_POINT = '/data/efs';

// ── Middleware ─────────────────────────────────────────────────────────────────
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// ── Routes ─────────────────────────────────────────────────────────────────────
app.use('/providers', providerRoutes);
app.use('/efs', efsRoutes);

// ── Health: liveness probe ─────────────────────────────────────────────────────
app.get('/health', (_req, res) => {
  res.json({ status: 'healthy', service: 'provider-service' });
});

// ── Health: deep status (Aurora + EFS) ────────────────────────────────────────
app.get('/health/status', async (_req, res) => {
  const results = await Promise.allSettled([

    // 1. Aurora — lightweight connectivity check
    (async () => {
      await pool.query('SELECT 1');
      return { service: 'aurora', status: 'connected' };
    })(),

    // 2. EFS — check mount point is accessible and writable
    (async () => {
      await fs.access(EFS_MOUNT_POINT, fsConstants.W_OK);
      return { service: 'efs', status: 'connected' };
    })(),

  ]);

  const status = {};
  const serviceNames = ['aurora', 'efs'];

  for (let i = 0; i < results.length; i++) {
    const result = results[i];
    const name = serviceNames[i];
    if (result.status === 'fulfilled') {
      status[name] = { status: result.value.status };
    } else {
      status[name] = { status: 'disconnected', error: result.reason?.message || 'unknown error' };
    }
  }

  logger.info({ action: 'health.status', services: status }, 'provider-service health checked');
  res.json(status);
});

// ── Global error handler ───────────────────────────────────────────────────────
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  logger.error({ error: err.message, stack: err.stack }, 'Unhandled error');
  res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

// ── Start ──────────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  logger.info({ port: PORT, service: 'provider-service' }, 'provider-service started');
});

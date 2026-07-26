import pino from 'pino';

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  // Pretty-print in development, plain JSON in production (better for CloudWatch)
  transport: process.env.NODE_ENV === 'development'
    ? { target: 'pino-pretty', options: { colorize: true } }
    : undefined,
  base: { service: 'architecting-pro' }
});

export default logger;

import pino from 'pino';

const isDev = process.env.NODE_ENV === 'development';

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  base: { service: 'provider-service' },
  transport: isDev
    ? { target: 'pino-pretty', options: { colorize: false, sync: true } }
    : undefined,
});

export default logger;

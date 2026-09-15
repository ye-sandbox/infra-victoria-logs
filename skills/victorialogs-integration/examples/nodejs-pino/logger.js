/**
 * Plug-and-Play Logger with Pino for Node.js / TypeScript.
 * 
 * Strictly emits NDJSON on stdout (1 JSON object per line),
 * compatible with Vector collector and VictoriaLogs indexing.
 */

const pino = require('pino');

const SERVICE_NAME = process.env.SERVICE_NAME || process.env.APP_NAME || 'app-nodejs';
const ENV_NAME = process.env.NODE_ENV || 'production';

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  messageKey: 'message',
  // Format log level in lowercase (info, error, warn, debug)
  formatters: {
    level: (label) => ({ level: label }),
  },
  // Inject canonical attributes into all emitted events
  base: {
    service: SERVICE_NAME,
    app: SERVICE_NAME,
    env: ENV_NAME,
  },
  // ISO-8601 UTC date format with 'timestamp' key
  timestamp: () => `,"timestamp":"${new Date().toISOString()}"`,
});

module.exports = { logger };

/**
 * Logger Plug-and-Play com Pino para Node.js / TypeScript.
 * 
 * Emite NDJSON estrito em stdout (1 objeto JSON por linha),
 * compatível com o coletor Vector e indexação VictoriaLogs.
 */

const pino = require('pino');

const SERVICE_NAME = process.env.SERVICE_NAME || process.env.APP_NAME || 'app-nodejs';
const ENV_NAME = process.env.NODE_ENV || 'production';

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  messageKey: 'message',
  // Formata o nível do log em minúsculas (info, error, warn, debug)
  formatters: {
    level: (label) => ({ level: label }),
  },
  // Injeta atributos canônicos em todos os eventos emitidos
  base: {
    service: SERVICE_NAME,
    app: SERVICE_NAME,
    env: ENV_NAME,
  },
  // Formato de data ISO-8601 UTC com chave 'timestamp'
  timestamp: () => `,"timestamp":"${new Date().toISOString()}"`,
});

module.exports = { logger };

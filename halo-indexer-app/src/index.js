const http = require('http');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const winston = require('winston');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const postsRouter = require('./routes/posts');
const moderationRouter = require('./routes/moderation');
const tlsRouter = require('./routes/tls');
const haloRouter = require('./routes/halo');
const messagingRouter = require('./routes/messaging');
const { startCharterAutoRefresh } = require('./services/charter');
const { initializeRedis, checkRedisHealth } = require('./services/redis');
const { attachMessagingWebSocket } = require('./ws/messaging');

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.simple(),
  transports: [new winston.transports.Console()]
});

const app = express();
const PORT = process.env.PORT || 3001;

app.use(helmet({
  // Allow WS upgrade from clients
  contentSecurityPolicy: false,
}));
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

app.use((req, _res, next) => { logger.info(`${req.method} ${req.url}`); next(); });

app.use('/api/posts', postsRouter);
app.use('/api/moderation', moderationRouter);
app.use('/api/tls', tlsRouter);
app.use('/api/halo', haloRouter);
app.use('/api/v1', messagingRouter);

app.get('/api/health', async (_req, res) => {
  try {
    const redisHealthy = await checkRedisHealth();
    const health = {
      ok: true,
      timestamp: new Date().toISOString(),
      services: {
        api: true,
        redis: redisHealthy,
        messaging: true,
      }
    };
    if (!redisHealthy) {
      return res.status(503).json({ ...health, ok: false, error: 'Redis is unavailable' });
    }
    res.json(health);
  } catch (error) {
    logger.error('Health check error:', error);
    res.status(503).json({
      ok: false,
      timestamp: new Date().toISOString(),
      error: 'Health check failed'
    });
  }
});

(async () => {
  try {
    await initializeRedis();
    logger.info('Redis initialized successfully');
    startCharterAutoRefresh(logger);

    const server = http.createServer(app);
    attachMessagingWebSocket(server);

    server.listen(PORT, () => {
      logger.info(`Halo Indexer running on :${PORT} (HTTP + Switchboard WS)`);
    });
  } catch (error) {
    logger.error('CRITICAL: Failed to initialize Redis. Server will not start.', error);
    process.exit(1);
  }
})();

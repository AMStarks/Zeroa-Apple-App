const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const winston = require('winston');
// Load .env from app root directory (not current working directory)
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const postsRouter = require('./routes/posts');
const moderationRouter = require('./routes/moderation');
const tlsRouter = require('./routes/tls');
const haloRouter = require('./routes/halo');
const { startCharterAutoRefresh } = require('./services/charter');
const { initializeRedis, checkRedisHealth } = require('./services/redis');

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.simple(),
  transports: [new winston.transports.Console()]
});

const app = express();
const PORT = process.env.PORT || 3001;

app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Basic request logger
app.use((req, _res, next) => { logger.info(`${req.method} ${req.url}`); next(); });

// Mount routes
app.use('/api/posts', postsRouter);
app.use('/api/moderation', moderationRouter);
app.use('/api/tls', tlsRouter); // Mount TLS router at /api/tls so routes become /api/tls/rpc and /api/tls/sign
app.use('/api/halo', haloRouter); // Mount Halo router at /api/halo so routes become /api/halo/challenge and /api/halo/verify

// Enhanced health check endpoint
app.get('/api/health', async (_req, res) => {
  try {
    const redisHealthy = await checkRedisHealth();
    const health = {
      ok: true,
      timestamp: new Date().toISOString(),
      services: {
        api: true,
        redis: redisHealthy
      }
    };
    
    // Return 503 if critical services are down
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

// Initialize Redis and start services - FAIL FAST if Redis is unavailable
(async () => {
  try {
    await initializeRedis();
    logger.info('Redis initialized successfully');
    
    // Start charter refresh
    startCharterAutoRefresh(logger);
    
    // Start server only after Redis is ready
    app.listen(PORT, () => {
      logger.info(`Halo Indexer (minimal) running on :${PORT}`);
    });
  } catch (error) {
    logger.error('CRITICAL: Failed to initialize Redis. Server will not start.', error);
    logger.error('This is a production-critical service. Exiting...');
    process.exit(1); // Fail fast - don't start without Redis
  }
})();
const redis = require('redis');

// Use a simple logger if utils/logger doesn't exist
let logger = console;
try {
  logger = require('../utils/logger');
} catch (e) {
  // Fallback to console
}

let redisClient = null;
let reconnectAttempts = 0;
const MAX_RECONNECT_ATTEMPTS = 10;
let reconnectTimer = null;

/**
 * Initialize Redis connection with automatic reconnection
 */
async function initializeRedis() {
  try {
    const redisUrl = process.env.REDIS_URL || 'redis://localhost:6379';
    
    redisClient = redis.createClient({
      url: redisUrl,
      socket: {
        reconnectStrategy: (retries) => {
          if (retries > MAX_RECONNECT_ATTEMPTS) {
            logger.error('Redis: Max reconnection attempts reached, giving up');
            return new Error('Max reconnection attempts reached');
          }
          reconnectAttempts = retries;
          const delay = Math.min(retries * 100, 3000);
          logger.warn(`Redis: Reconnection attempt ${retries}/${MAX_RECONNECT_ATTEMPTS} in ${delay}ms`);
          return delay;
        }
      }
    });

    redisClient.on('error', (err) => {
      logger.error('Redis client error:', err);
      // Don't throw - let reconnection handle it
    });

    redisClient.on('connect', () => {
      logger.info('Redis: Client connecting...');
      reconnectAttempts = 0;
    });

    redisClient.on('ready', () => {
      logger.info('Redis: Client ready and connected');
      reconnectAttempts = 0;
      if (reconnectTimer) {
        clearTimeout(reconnectTimer);
        reconnectTimer = null;
      }
    });

    redisClient.on('end', () => {
      logger.warn('Redis: Client disconnected');
    });

    redisClient.on('reconnecting', () => {
      logger.info(`Redis: Reconnecting (attempt ${reconnectAttempts + 1})...`);
    });

    await redisClient.connect();
    
    // Test connection
    await redisClient.ping();
    logger.info('Redis: Connection established successfully');
    
    reconnectAttempts = 0;
    
  } catch (error) {
    logger.error('Redis: Failed to initialize:', error);
    throw error; // Fail fast - don't start server without Redis
  }
}

/**
 * Get Redis client instance with health check
 * @returns {RedisClient} Redis client
 * @throws {Error} If Redis is not initialized or disconnected
 */
function getRedisClient() {
  if (!redisClient) {
    throw new Error('Redis client not initialized');
  }
  
  // Check if client is still connected
  if (!redisClient.isOpen) {
    throw new Error('Redis client is disconnected. Reconnection in progress...');
  }
  
  return redisClient;
}

/**
 * Health check for Redis connection
 * @returns {Promise<boolean>} True if Redis is healthy
 */
async function checkRedisHealth() {
  try {
    if (!redisClient || !redisClient.isOpen) {
      return false;
    }
    await redisClient.ping();
    return true;
  } catch (error) {
    logger.error('Redis health check failed:', error);
    return false;
  }
}

/**
 * Store post data in Redis
 * @param {string} postId - Post identifier
 * @param {object} postData - Post data to store
 */
async function storePost(postId, postData) {
  try {
    const client = getRedisClient();
    const postKey = `halo:post:${postId}`;
    
    // Store each field individually
    const postDataWithTimestamp = {
      ...postData,
      createdAt: new Date().toISOString()
    };
    
    // Store each field individually (skip null/undefined; coerce to string)
    for (const [key, value] of Object.entries(postDataWithTimestamp)) {
      if (value === null || value === undefined) {
        continue;
      }
      await client.hSet(postKey, key, String(value));
    }
    // Ensure numeric counters exist for top-level posts
    const isTopLevel = (!postData.parentSequentialCode || String(postData.parentSequentialCode).length === 0) && (!postData.parentIpfsHash || String(postData.parentIpfsHash).length === 0);
    if (isTopLevel) {
      const hasReplies = await client.hGet(postKey, 'repliesCount');
      if (hasReplies === null) {
        await client.hSet(postKey, 'repliesCount', '0');
      }
      const hasLikes = await client.hGet(postKey, 'likesCount');
      if (hasLikes === null) {
        await client.hSet(postKey, 'likesCount', '0');
      }
    }
    
    // Add to chronological feed ONLY for top-level posts (no parent)
    if (isTopLevel) {
      await client.zAdd('halo:feed:chronological', { score: postData.timestamp, value: postId });
    }
    
    // Add to user's posts
    if (postData.userAddress) {
      await client.zAdd(`halo:user:${postData.userAddress}:posts`, { score: postData.timestamp, value: postId });
    }

    // Index replies by parent to support fetching comment threads
    if (postData.parentSequentialCode && postData.parentSequentialCode.length > 0) {
      const key = `halo:replies:parent:${postData.parentSequentialCode}`;
      await client.zAdd(key, { score: postData.timestamp, value: postId });
      // Increment parent's repliesCount
      const parentKey = `halo:post:${postData.parentSequentialCode}`;
      await client.hIncrBy(parentKey, 'repliesCount', 1);
    }
    if (postData.parentIpfsHash && postData.parentIpfsHash.length > 0) {
      const key = `halo:replies:parentipfs:${postData.parentIpfsHash}`;
      await client.zAdd(key, { score: postData.timestamp, value: postId });
      const parentKey = `halo:post:${postData.parentIpfsHash}`;
      await client.hIncrBy(parentKey, 'repliesCount', 1);
    }
    
    logger.info('Post stored in Redis', { postId, userAddress: postData.userAddress?.slice(0, 10) + '...' });
    
  } catch (error) {
    logger.error('Failed to store post in Redis', error);
    throw error;
  }
}

/**
 * Get post data from Redis
 * @param {string} postId - Post identifier
 * @returns {object|null} Post data or null if not found
 */
async function getPost(postId) {
  try {
    const client = getRedisClient();
    const postKey = `halo:post:${postId}`;
    
    const postData = await client.hGetAll(postKey);
    return Object.keys(postData).length > 0 ? postData : null;
    
  } catch (error) {
    logger.error('Failed to get post from Redis', error);
    return null;
  }
}

/**
 * Get chronological feed
 * @param {number} start - Start index
 * @param {number} count - Number of posts to retrieve
 * @returns {Array} Array of post IDs in chronological order
 */
async function getChronologicalFeed(start = 0, count = 50) {
  try {
    const client = getRedisClient();
    
    // Get post IDs in reverse chronological order (newest first)
    let postIds = [];
    try {
      postIds = await client.zRange('halo:feed:chronological', start, start + count - 1, { REV: true });
    } catch (e) {
      if (typeof client.zRevRange === 'function') {
        postIds = await client.zRevRange('halo:feed:chronological', start, start + count - 1);
      } else {
        const forward = await client.zRange('halo:feed:chronological', 0, start + count - 1);
        postIds = forward.slice(start).reverse();
      }
    }
    
    // Get full post data for each ID and FILTER OUT replies defensively
    const posts = [];
    for (const postId of postIds) {
      const postData = await getPost(postId);
      if (!postData) continue;
      const hasParent = (postData.parentSequentialCode && postData.parentSequentialCode.length > 0) || (postData.parentIpfsHash && postData.parentIpfsHash.length > 0);
      if (hasParent) continue;
      posts.push(postData);
    }
    
    return posts;
    
  } catch (error) {
    logger.error('Failed to get chronological feed', error);
    return [];
  }
}

/**
 * Get posts for a specific user
 * @param {string} userAddress - TLS address
 * @param {number} start - Start index
 * @param {number} count - Number of posts to retrieve
 * @returns {Array} Array of post objects for the user
 */
async function getUserPosts(userAddress, start = 0, count = 50) {
  try {
    const client = getRedisClient();
    const key = `halo:user:${userAddress}:posts`;
    let postIds = [];
    try {
      postIds = await client.zRange(key, start, start + count - 1, { REV: true });
    } catch (e) {
      if (typeof client.zRevRange === 'function') {
        postIds = await client.zRevRange(key, start, start + count - 1);
      } else {
        const forward = await client.zRange(key, 0, start + count - 1);
        postIds = forward.slice(start).reverse();
      }
    }
    const posts = [];
    for (const postId of postIds) {
      const postData = await getPost(postId);
      if (postData) posts.push(postData);
    }
    return posts;
  } catch (error) {
    logger.error('Failed to get user posts', error);
    return [];
  }
}

/**
 * Store sequential code metadata
 * @param {string} sequentialCode - Sequential code
 * @param {object} metadata - Code metadata
 */
async function storeSequentialCode(sequentialCode, metadata) {
  try {
    const client = getRedisClient();
    const codeKey = `halo:code:${sequentialCode}`;
    
    // Store each field individually
    const metadataWithTimestamp = {
      ...metadata,
      createdAt: new Date().toISOString()
    };
    
    // Store each field individually
    for (const [key, value] of Object.entries(metadataWithTimestamp)) {
      await client.hSet(codeKey, key, value);
    }
    
    // Add to chronological index
    await client.zAdd('halo:codes:chronological', { score: metadata.timestamp, value: sequentialCode });
    
    logger.info('Sequential code stored', { sequentialCode });
    
  } catch (error) {
    logger.error('Failed to store sequential code', error);
    throw error;
  }
}

/**
 * Get sequential code metadata
 * @param {string} sequentialCode - Sequential code
 * @returns {object|null} Code metadata or null if not found
 */
async function getSequentialCode(sequentialCode) {
  try {
    const client = getRedisClient();
    const codeKey = `halo:code:${sequentialCode}`;
    
    const metadata = await client.hGetAll(codeKey);
    return Object.keys(metadata).length > 0 ? metadata : null;
    
  } catch (error) {
    logger.error('Failed to get sequential code', error);
    return null;
  }
}

/**
 * Rate limiting helper
 * @param {string} key - Rate limit key
 * @param {number} window - Time window in seconds
 * @param {number} limit - Maximum requests per window
 * @returns {boolean} True if within rate limit
 */
async function checkRateLimit(key, window, limit) {
  try {
    const client = getRedisClient();
    const rateLimitKey = `halo:rate_limit:${key}`;
    
    const current = await client.get(rateLimitKey);
    const count = current ? parseInt(current) : 0;
    
    if (count >= limit) {
      return false;
    }
    
    await client.incr(rateLimitKey);
    await client.expire(rateLimitKey, window);
    
    return true;
    
  } catch (error) {
    logger.error('Rate limit check failed', error);
    return true; // Allow if rate limiting fails
  }
}

/**
 * Clean up Redis connection
 */
async function closeRedis() {
  if (redisClient) {
    await redisClient.quit();
    logger.info('Redis connection closed');
  }
}

// Subscription helpers
async function getSubscriptionActiveUntil(userAddress) {
  try {
    const client = getRedisClient();
    const key = `halo:subs:active:${userAddress}`;
    const v = await client.get(key);
    return v ? Number(v) : 0;
  } catch (e) {
    logger.error('getSubscriptionActiveUntil error', e);
    return 0;
  }
}

/**
 * Store user profile data in Redis
 * @param {string} userAddress - User TLS address
 * @param {object} profileData - Profile data (name, bio, etc.)
 */
async function storeUserProfile(userAddress, profileData) {
  try {
    const client = getRedisClient();
    const key = `halo:profile:${userAddress}`;
    
    // Store each field
    for (const [field, value] of Object.entries(profileData)) {
      if (value !== null && value !== undefined) {
        await client.hSet(key, field, String(value));
      }
    }
    
    // Set expiration (optional, e.g., 30 days)
    await client.expire(key, 30 * 24 * 60 * 60);
    
    return true;
  } catch (error) {
    logger.error('storeUserProfile error', error);
    return false;
  }
}

/**
 * Get user profile data from Redis
 * @param {string} userAddress - User TLS address
 * @returns {object|null} Profile data or null if not found
 */
async function getUserProfile(userAddress) {
  try {
    const client = getRedisClient();
    
    const key = `halo:profile:${userAddress}`;
    
    const profile = await client.hGetAll(key);
    return Object.keys(profile).length > 0 ? profile : null;
  } catch (error) {
    logger.error('getUserProfile error', error);
    return null;
  }
}

/**
 * Get multiple user profiles from Redis
 * @param {string[]} userAddresses - Array of user TLS addresses
 * @returns {object} Object mapping addresses to profile data
 */
async function getUserProfiles(userAddresses) {
  try {
    const client = getRedisClient();
    const profiles = {};
    
    // Fetch all profiles in parallel
    const promises = userAddresses.map(async (address) => {
      const key = `halo:profile:${address}`;
      const profile = await client.hGetAll(key);
      if (Object.keys(profile).length > 0) {
        profiles[address] = profile;
      }
    });
    
    await Promise.all(promises);
    return profiles;
  } catch (error) {
    logger.error("getUserProfiles error", error);
    return {};
  }
}

module.exports = {
  initializeRedis,
  getRedisClient,
  checkRedisHealth,
  storePost,
  getPost,
  getChronologicalFeed,
  getUserPosts,
  checkRateLimit,
  storeUserProfile,
  getUserProfile,
  getUserProfiles,
  closeRedis,
  getSubscriptionActiveUntil,
};


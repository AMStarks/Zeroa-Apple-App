const express = require('express');
const router = express.Router();
const { evaluateModeration } = require('../services/moderation');
const { getPost, storePost, getChronologicalFeed, getUserPosts, getRedisClient } = require('../services/redis');

// Helper function to calculate deep reply count (total descendants) from Redis
async function calculateDeepRepliesCount(postId) {
  try {
    const client = getRedisClient();
    const directRepliesKey = `halo:replies:parent:${postId}`;
    const directRepliesIpfsKey = `halo:replies:parentipfs:${postId}`;
    
    // Get direct replies by parentSequentialCode
    let directReplies = [];
    try {
      const seqReplies = await client.zRange(directRepliesKey, 0, -1);
      directReplies = seqReplies || [];
    } catch (e) {
      // Key doesn't exist, no replies
    }
    
    // Get direct replies by parentIpfsHash
    try {
      const ipfsReplies = await client.zRange(directRepliesIpfsKey, 0, -1);
      if (ipfsReplies) {
        directReplies = [...new Set([...directReplies, ...ipfsReplies])];
      }
    } catch (e) {
      // Key doesn't exist, no replies
    }
    
    let totalCount = directReplies.length;
    
    // Recursively count nested replies
    for (const replyId of directReplies) {
      totalCount += await calculateDeepRepliesCount(replyId);
    }
    
    return totalCount;
  } catch (error) {
    console.error('Error calculating deep replies count:', error);
    return 0;
  }
}

// Helper function to get replies for a post from Redis
async function getRepliesForPost(postId) {
  try {
    const client = getRedisClient();
    const replies = [];
    
    // Get replies by parentSequentialCode
    const seqKey = `halo:replies:parent:${postId}`;
    try {
      const seqReplyIds = await client.zRange(seqKey, 0, -1);
      for (const replyId of seqReplyIds || []) {
        const reply = await getPost(replyId);
        if (reply) replies.push(reply);
      }
    } catch (e) {
      // No replies
    }
    
    // Get replies by parentIpfsHash
    const ipfsKey = `halo:replies:parentipfs:${postId}`;
    try {
      const ipfsReplyIds = await client.zRange(ipfsKey, 0, -1);
      for (const replyId of ipfsReplyIds || []) {
        const reply = await getPost(replyId);
        if (reply && !replies.find(r => r.id === reply.id)) {
          replies.push(reply);
        }
      }
    } catch (e) {
      // No replies
    }
    
    return replies;
  } catch (error) {
    console.error('Error getting replies:', error);
    return [];
  }
}

// Helper function to recursively collect all replies for a thread
async function collectAllReplies(postId, collected = [], limit = 200) {
  if (collected.length >= limit) return collected;
  
  const directReplies = await getRepliesForPost(postId);
  
  for (const reply of directReplies) {
    if (collected.length >= limit) break;
    if (!collected.find(r => r.id === reply.id)) {
      collected.push(reply);
      await collectAllReplies(reply.id, collected, limit);
    }
  }
  
  return collected;
}

// Convert Redis hash to post object with proper types
function redisHashToPost(hash) {
  if (!hash || Object.keys(hash).length === 0) return null;
  
  return {
    id: hash.id || '',
    userAddress: hash.userAddress || 'unknown',
    signature: hash.signature || '',
    pubkey: hash.pubkey || '',
    timestamp: hash.timestamp || String(Date.now()),
    postType: hash.postType || 'free',
    content: hash.content || '',
    createdAt: hash.createdAt || new Date().toISOString(),
    likesCount: parseInt(hash.likesCount || '0', 10),
    repliesCount: parseInt(hash.repliesCount || '0', 10),
    deepRepliesCount: parseInt(hash.deepRepliesCount || '0', 10),
    tlsCount: parseInt(hash.tlsCount || '0', 10),
    parentSequentialCode: hash.parentSequentialCode || '',
    parentIpfsHash: hash.parentIpfsHash || '',
    sequentialCode: hash.id || hash.sequentialCode || '',
    code: hash.id || hash.code || ''
  };
}

router.get('/:id', async (req, res) => {
  try {
    const id = req.params.id.replace('%23', '#');
    const postData = await getPost(id);
    if (!postData) return res.status(404).json({ error: 'Not found' });
    
    const post = redisHashToPost(postData);
    // Calculate deep replies count
    post.deepRepliesCount = await calculateDeepRepliesCount(id);
    
    res.json({ success: true, data: post });
  } catch (error) {
    console.error('Error getting post:', error);
    res.status(500).json({ error: 'Failed to get post' });
  }
});

router.post('/', async (req, res) => {
  try {
    const previewEnabled = String(req.get('X-Moderation-Preview') || '').toLowerCase() === 'true';
    const { content, userAddress, signature, pubkey, timestamp, postType, parentSequentialCode, parentIpfsHash, profileName, profileBio, profileImageBase64 } = req.body || {};
    if (typeof content !== 'string' || !content.trim()) return res.status(400).json({ error: 'Invalid content' });
    if (previewEnabled) {
      const decision = evaluateModeration(content, { postType });
      if (decision?.action === 'hard_block') {
        return res.status(422).json({ error: 'Moderation blocked', message: 'Content violates moderation policy', decision });
      }
    }
    const id = parentSequentialCode ? parentSequentialCode : (parentIpfsHash ? parentIpfsHash : `LAS#${Date.now()}`);
    const postTimestamp = String(timestamp || Date.now());
    
    const post = {
      id,
      userAddress: userAddress || 'unknown',
      signature: signature || '',
      pubkey: pubkey || '',
      timestamp: postTimestamp,
      postType: postType || 'free',
      content: content.trim(),
      createdAt: new Date().toISOString(),
      likesCount: 0,
      repliesCount: 0,
      deepRepliesCount: 0,
      tlsCount: 0,
      parentSequentialCode: parentSequentialCode || '',
      parentIpfsHash: parentIpfsHash || ''
    };
    
    // Store post in Redis
    await storePost(id, post);
    
    // Store profile data if provided
    if (profileName || profileBio || profileImageBase64) {
      const { storeUserProfile } = require('../services/redis');
      await storeUserProfile(userAddress, {
        name: profileName,
        bio: profileBio,
        image: profileImageBase64
      });
    }
    
    // Get the stored post back
    const storedPostData = await getPost(id);
    const updatedPost = redisHashToPost(storedPostData);
    updatedPost.deepRepliesCount = await calculateDeepRepliesCount(id);
    
    res.status(201).json({ success: true, data: updatedPost, sequentialCode: id });
  } catch (e) {
    console.error('Error creating post:', e);
    res.status(500).json({ error: 'Failed to create post' });
  }
});

router.get('/:id/replies', async (req, res) => {
  try {
    const root = req.params.id.replace('%23', '#');
    const replies = await getRepliesForPost(root);
    const formattedReplies = replies.map(redisHashToPost);
    res.json({ success: true, data: formattedReplies });
  } catch (error) {
    console.error('Error getting replies:', error);
    res.status(500).json({ error: 'Failed to get replies' });
  }
});

// New thread endpoint - returns entire comment tree for a post
router.get('/:id/thread', async (req, res) => {
  try {
    const root = req.params.id.replace('%23', '#');
    const limit = Math.max(1, Math.min(500, parseInt(req.query.limit || '200', 10)));
    
    const allReplies = await collectAllReplies(root, [], limit);
    const formattedReplies = allReplies.map(redisHashToPost);
    res.json({ success: true, data: formattedReplies, totalCount: formattedReplies.length });
  } catch (error) {
    console.error('Error getting thread:', error);
    res.status(500).json({ error: 'Failed to get thread' });
  }
});

// Alternative thread endpoint via query parameter
router.get('/', async (req, res) => {
  try {
    // Check if this is a thread request
    if (req.query.thread === '1' && req.query.sequentialCode) {
      const root = req.query.sequentialCode.replace('%23', '#');
      const limit = Math.max(1, Math.min(500, parseInt(req.query.limit || '200', 10)));
      
      const allReplies = await collectAllReplies(root, [], limit);
      const formattedReplies = allReplies.map(redisHashToPost);
      return res.json({ success: true, data: formattedReplies, totalCount: formattedReplies.length });
    }
    
    // Check if this is a user posts request
    if (req.query.userAddress || req.path.includes('/users/')) {
      const userAddress = req.query.userAddress || req.path.split('/users/')[1]?.split('/')[0];
      if (userAddress) {
        const page = Math.max(0, parseInt(req.query.page || '0', 10));
        const limit = Math.max(1, Math.min(100, parseInt(req.query.limit || '50', 10)));
        const start = page * limit;
        
        const userPosts = await getUserPosts(userAddress, start, limit);
        const formattedPosts = userPosts.map(redisHashToPost);
        
        // Calculate deep replies count for each post
        for (const post of formattedPosts) {
          post.deepRepliesCount = await calculateDeepRepliesCount(post.id);
        }
        
        return res.json({ 
          success: true, 
          data: formattedPosts, 
          pagination: { 
            page, 
            limit, 
            total: formattedPosts.length,
            hasMore: formattedPosts.length === limit 
          } 
        });
      }
    }
    
    // Regular posts feed (chronological)
    const page = Math.max(0, parseInt(req.query.page || '0', 10));
    const limit = Math.max(1, Math.min(100, parseInt(req.query.limit || '50', 10)));
    const start = page * limit;
    
    const feedPosts = await getChronologicalFeed(start, limit);
    const formattedPosts = feedPosts.map(redisHashToPost);
    
    // Calculate deep replies count for each post
    for (const post of formattedPosts) {
      post.deepRepliesCount = await calculateDeepRepliesCount(post.id);
    }
    
    // Get total count (approximate)
    const client = getRedisClient();
    const totalCount = await client.zCard('halo:feed:chronological').catch(() => formattedPosts.length);
    
    res.json({ 
      success: true, 
      data: formattedPosts, 
      pagination: { 
        page, 
        limit, 
        total: totalCount,
        hasMore: formattedPosts.length === limit && (start + limit) < totalCount 
      } 
    });
  } catch (error) {
    console.error('Error getting posts:', error);
    res.status(500).json({ error: 'Failed to get posts' });
  }
});

// POST /api/posts/:id/reward - Reward a post with TLS
router.post('/:id/reward', async (req, res) => {
  try {
    const postId = req.params.id.replace('%23', '#');
    const { fromAddress, amount = 10.0 } = req.body || {};
    
    // Get post from Redis
    const postData = await getPost(postId);
    if (!postData) {
      return res.status(404).json({ error: 'Post not found' });
    }
    
    // Increment TLS count in Redis
    const client = getRedisClient();
    const postKey = `halo:post:${postId}`;
    const newTlsCount = await client.hIncrBy(postKey, 'tlsCount', 1);
    
    // Log the reward (for blockchain settlement queue - future implementation)
    console.log(`TLS Reward: Post ${postId}, From: ${fromAddress || 'unknown'}, To: ${postData.userAddress}, Amount: ${amount}, New Count: ${newTlsCount}`);
    
    res.json({ 
      success: true, 
      data: {
        postId,
        tlsCount: newTlsCount,
        fromAddress: fromAddress || 'unknown',
        toAddress: postData.userAddress,
        amount
      }
    });
  } catch (e) {
    console.error('Error rewarding post:', e);
    res.status(500).json({ error: 'Failed to reward post' });
  }
});

module.exports = router;

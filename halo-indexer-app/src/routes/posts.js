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
async function redisHashToPost(hash) {
  if (!hash || Object.keys(hash).length === 0) return null;
  
  const post = {
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
  
  return post;
}

router.get('/:id', async (req, res) => {
  try {
    const id = req.params.id.replace('%23', '#');
    const postData = await getPost(id);
    if (!postData) return res.status(404).json({ error: 'Not found' });
    
    const post = await redisHashToPost(postData);
    if (!post) return res.status(404).json({ error: 'Not found' });
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
      const profileData = {};
      if (profileName) profileData.name = profileName;
      if (profileBio) profileData.bio = profileBio;
      if (profileImageBase64) profileData.image = profileImageBase64;
      await storeUserProfile(userAddress, profileData);
      console.log(`✅ Stored profile data for ${userAddress}: name=${!!profileName}, bio=${!!profileBio}, image=${!!profileImageBase64}`);
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
    const formattedReplies = await Promise.all(replies.map(redisHashToPost));
    res.json({ success: true, data: formattedReplies.filter(p => p !== null) });
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
    const formattedReplies = await Promise.all(allReplies.map(redisHashToPost));
    res.json({ success: true, data: formattedReplies.filter(p => p !== null), totalCount: formattedReplies.length });
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
      const formattedReplies = await Promise.all(allReplies.map(redisHashToPost));
      return res.json({ success: true, data: formattedReplies.filter(p => p !== null), totalCount: formattedReplies.length });
    }
    
    // Check if this is a user posts request
    if (req.query.userAddress || req.path.includes('/users/')) {
      const userAddress = req.query.userAddress || req.path.split('/users/')[1]?.split('/')[0];
      if (userAddress) {
        const page = Math.max(0, parseInt(req.query.page || '0', 10));
        const limit = Math.max(1, Math.min(100, parseInt(req.query.limit || '50', 10)));
        const start = page * limit;
        
        const userPosts = await getUserPosts(userAddress, start, limit);
        const formattedPosts = await Promise.all(userPosts.map(redisHashToPost));
        const validPosts = formattedPosts.filter(p => p !== null);
        
        // Calculate deep replies count for each post
        for (const post of validPosts) {
          post.deepRepliesCount = await calculateDeepRepliesCount(post.id);
        }
        
        return res.json({ 
          success: true, 
          data: validPosts, 
          pagination: { 
            page, 
            limit, 
            total: validPosts.length,
            hasMore: validPosts.length === limit 
          } 
        });
      }
    }
    
    // Regular posts feed (chronological)
    const page = Math.max(0, parseInt(req.query.page || '0', 10));
    const limit = Math.max(1, Math.min(100, parseInt(req.query.limit || '50', 10)));
    const start = page * limit;
    
    const feedPosts = await getChronologicalFeed(start, limit);
    const formattedPosts = await Promise.all(feedPosts.map(redisHashToPost));
    const validPosts = formattedPosts.filter(p => p !== null);
    
    // Fetch profile data for all posts in batch
    const { getUserProfiles } = require('../services/redis');
    const userAddresses = [...new Set(validPosts.map(p => p.userAddress).filter(addr => addr && addr !== 'unknown'))];
    console.log(`[PROFILE] Fetching profiles for ${userAddresses.length} addresses:`, userAddresses.slice(0, 3));
    if (userAddresses.length > 0) {
      try {
        const profiles = await getUserProfiles(userAddresses);
        console.log(`[PROFILE] Got ${Object.keys(profiles).length} profiles. Keys:`, Object.keys(profiles).slice(0, 3));
        console.log(`[PROFILE] Sample profile data:`, profiles[userAddresses[0]] ? Object.keys(profiles[userAddresses[0]]) : 'No profile for first address');
        // Enrich posts with profile data
        let enriched = 0;
        for (const post of validPosts) {
          if (post.userAddress && profiles[post.userAddress]) {
            const profile = profiles[post.userAddress];
            console.log(`[PROFILE] Post ${post.id} user ${post.userAddress}: profile keys:`, Object.keys(profile));
            // Check for both 'name' and 'profileName' keys (for backwards compatibility)
            const profileName = profile.name || profile.profileName;
            if (profileName && profileName !== 'null' && profileName !== '' && profileName !== 'undefined') {
              post.profileName = String(profileName);
              enriched++;
              console.log(`[PROFILE] Set profileName for ${post.userAddress}: ${profileName.substring(0, 20)}`);
            } else {
              console.log(`[PROFILE] No valid profileName for ${post.userAddress}. profileName value:`, profileName);
            }
            const profileBio = profile.bio || profile.profileBio;
            if (profileBio && profileBio !== 'null' && profileBio !== '' && profileBio !== 'undefined') {
              post.profileBio = String(profileBio);
            }
            const profileImage = profile.image || profile.profileImage;
            if (profileImage && profileImage !== 'null' && profileImage !== '' && profileImage !== 'undefined') {
              post.profileImage = String(profileImage);
            }
          } else {
            console.log(`[PROFILE] No profile for post ${post.id} user ${post.userAddress}. Has userAddress: ${!!post.userAddress}, Has profile: ${!!profiles[post.userAddress]}`);
          }
        }
        console.log(`[PROFILE] Enriched ${enriched} posts with profile names. Total posts: ${validPosts.length}`);
        console.log(`[PROFILE] Sample post after enrichment:`, JSON.stringify(validPosts[0]).substring(0, 200));
      } catch (error) {
        console.error('[PROFILE] Error enriching posts with profile data:', error);
        console.error('[PROFILE] Error stack:', error.stack);
      }
    } else {
      console.log(`[PROFILE] No user addresses to fetch profiles for`);
    }
    
    // Calculate deep replies count for each post
    for (const post of validPosts) {
      post.deepRepliesCount = await calculateDeepRepliesCount(post.id);
    }
    
    // Get total count (approximate)
    const client = getRedisClient();
    const totalCount = await client.zCard('halo:feed:chronological').catch(() => formattedPosts.length);
    
    res.json({ 
      success: true, 
      data: validPosts, 
      pagination: { 
        page, 
        limit, 
        total: totalCount,
        hasMore: validPosts.length === limit && (start + limit) < totalCount 
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

// DELETE /api/posts/by-timestamp - Delete posts by timestamp (admin only)
router.delete('/by-timestamp', async (req, res) => {
  try {
    const { timestamps } = req.body; // Array of timestamps in milliseconds
    if (!Array.isArray(timestamps) || timestamps.length === 0) {
      return res.status(400).json({ error: 'timestamps array required' });
    }

    const client = getRedisClient();
    const deletedPosts = [];
    const errors = [];

    // Get all post IDs from chronological feed
    const allPostIds = await client.zRange('halo:feed:chronological', 0, -1);
    
    for (const postId of allPostIds) {
      const postData = await getPost(postId);
      if (!postData) continue;

      const postTimestamp = parseInt(postData.timestamp, 10);
      if (timestamps.includes(postTimestamp)) {
        try {
          // Delete from main post hash
          await client.del(`halo:post:${postId}`);
          
          // Delete from chronological feed
          await client.zRem('halo:feed:chronological', postId);
          
          // Delete from user's posts
          if (postData.userAddress) {
            await client.zRem(`halo:user:${postData.userAddress}:posts`, postId);
          }
          
          // Delete from reply indexes
          if (postData.parentSequentialCode) {
            await client.zRem(`halo:replies:parent:${postData.parentSequentialCode}`, postId);
            // Decrement parent's repliesCount
            const parentKey = `halo:post:${postData.parentSequentialCode}`;
            const currentCount = await client.hGet(parentKey, 'repliesCount');
            if (currentCount) {
              await client.hIncrBy(parentKey, 'repliesCount', -1);
            }
          }
          if (postData.parentIpfsHash) {
            await client.zRem(`halo:replies:parentipfs:${postData.parentIpfsHash}`, postId);
            const parentKey = `halo:post:${postData.parentIpfsHash}`;
            const currentCount = await client.hGet(parentKey, 'repliesCount');
            if (currentCount) {
              await client.hIncrBy(parentKey, 'repliesCount', -1);
            }
          }

          deletedPosts.push({ postId, timestamp: postTimestamp });
          console.log(`Deleted post: ${postId} (timestamp: ${postTimestamp})`);
        } catch (error) {
          errors.push({ postId, error: error.message });
          console.error(`Error deleting post ${postId}:`, error);
        }
      }
    }

    res.json({
      success: true,
      deleted: deletedPosts.length,
      deletedPosts,
      errors: errors.length > 0 ? errors : undefined
    });
  } catch (error) {
    console.error('Error deleting posts by timestamp:', error);
    res.status(500).json({ error: 'Failed to delete posts', message: error.message });
  }
});

module.exports = router;

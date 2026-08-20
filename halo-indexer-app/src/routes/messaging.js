const express = require('express');
const { requireHaloAuth } = require('../middleware/auth');
const messaging = require('../services/messaging');

const router = express.Router();

router.post('/message/relay', requireHaloAuth, async (req, res) => {
  try {
    const {
      sender_address,
      receiver_address,
      encrypted_content,
      message_type = 'text',
      signature,
      sender_pubkey,
      timestamp,
    } = req.body || {};

    if (!sender_address || !receiver_address || !encrypted_content || !signature) {
      return res.status(400).json({
        success: false,
        error: 'sender_address, receiver_address, encrypted_content, and signature are required',
      });
    }

    if (messaging.normalizeAddress(sender_address) !== messaging.normalizeAddress(req.haloUser.address)) {
      return res.status(403).json({ success: false, error: 'sender_address must match authenticated address' });
    }

    if (message_type && message_type !== 'text') {
      return res.status(400).json({ success: false, error: 'Only text messages are supported' });
    }

    const result = await messaging.relayMessage({
      sender_address,
      receiver_address,
      encrypted_content,
      message_type: 'text',
      signature,
      sender_pubkey: sender_pubkey || '',
      timestamp: timestamp || new Date().toISOString(),
    });

    res.json(result);
  } catch (error) {
    console.error('message/relay error:', error);
    res.status(500).json({ success: false, error: error.message || 'Relay failed' });
  }
});

router.post('/peer/register', requireHaloAuth, async (req, res) => {
  try {
    const { address, public_key, connection_info, is_online } = req.body || {};
    const addr = messaging.normalizeAddress(address || req.haloUser.address);
    if (addr !== messaging.normalizeAddress(req.haloUser.address)) {
      return res.status(403).json({ success: false, error: 'Can only register own address' });
    }
    if (!public_key) {
      return res.status(400).json({ success: false, error: 'public_key required' });
    }
    await messaging.registerPeer({
      address: addr,
      publicKey: public_key,
      connectionInfo: connection_info || { websocket: true },
      isOnline: is_online !== false,
    });
    res.json({ success: true });
  } catch (error) {
    console.error('peer/register error:', error);
    res.status(500).json({ success: false, error: error.message || 'Register failed' });
  }
});

router.get('/peer/:address', requireHaloAuth, async (req, res) => {
  try {
    const peer = await messaging.getPeer(req.params.address);
    if (!peer) return res.status(404).json({ success: false, error: 'Peer not found' });
    res.json({ success: true, peer });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message || 'Lookup failed' });
  }
});

router.get('/peers/discover', requireHaloAuth, async (req, res) => {
  try {
    const address = messaging.normalizeAddress(req.query.address || req.haloUser.address);
    const peers = await messaging.listOnlinePeers(address);
    res.json({ success: true, peers, count: peers.length });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message || 'Discover failed' });
  }
});

router.get('/messages/:address', requireHaloAuth, async (req, res) => {
  try {
    const address = messaging.normalizeAddress(req.params.address);
    if (address !== messaging.normalizeAddress(req.haloUser.address)) {
      return res.status(403).json({ success: false, error: 'Can only fetch own inbox' });
    }
    const limit = Math.min(200, Math.max(1, Number(req.query.limit) || 100));
    const messages = await messaging.getMessagesForAddress(address, { limit });
    res.json({ success: true, messages, count: messages.length });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message || 'Inbox failed' });
  }
});

router.get('/messaging/health', (_req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
  });
});

module.exports = router;

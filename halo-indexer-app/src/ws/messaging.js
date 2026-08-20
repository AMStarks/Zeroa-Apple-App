const { WebSocketServer } = require('ws');
const { verifyJWTFromQueryOrHeader, verifyJWT } = require('../middleware/auth');
const messaging = require('../services/messaging');

function extractToken(req) {
  const url = new URL(req.url, 'http://localhost');
  if (url.searchParams.get('token')) return url.searchParams.get('token');
  const header = req.headers['authorization'] || '';
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : null;
}

function attachMessagingWebSocket(server) {
  const wss = new WebSocketServer({ noServer: true });

  server.on('upgrade', (req, socket, head) => {
    try {
      const url = new URL(req.url, 'http://localhost');
      const match = url.pathname.match(/^\/ws\/([^/]+)$/);
      if (!match) {
        socket.destroy();
        return;
      }
      const address = decodeURIComponent(match[1]);
      const token = extractToken(req);
      const payload = token ? verifyJWT(token) : null;
      if (!payload || messaging.normalizeAddress(payload.address) !== messaging.normalizeAddress(address)) {
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        socket.destroy();
        return;
      }

      wss.handleUpgrade(req, socket, head, (ws) => {
        wss.emit('connection', ws, req, address);
      });
    } catch (error) {
      console.error('WS upgrade error:', error);
      socket.destroy();
    }
  });

  wss.on('connection', async (ws, _req, address) => {
    const addr = messaging.normalizeAddress(address);
    messaging.attachSocket(addr, ws);
    try {
      const existing = await messaging.getPeer(addr);
      await messaging.registerPeer({
        address: addr,
        publicKey: existing?.public_key || '',
        connectionInfo: { websocket: true },
        isOnline: true,
      });
    } catch (e) {
      console.error('WS register peer error:', e);
    }

    ws.send(
      JSON.stringify({
        type: 'connected',
        address: addr,
        timestamp: new Date().toISOString(),
      })
    );

    ws.on('message', async (raw) => {
      try {
        const parsed = JSON.parse(String(raw));
        if (parsed.type === 'ping') {
          ws.send(JSON.stringify({ type: 'pong', timestamp: new Date().toISOString() }));
          return;
        }
        if (parsed.type === 'message' && parsed.data) {
          const data = parsed.data;
          if (messaging.normalizeAddress(data.sender_address) !== addr) {
            ws.send(JSON.stringify({ type: 'error', error: 'sender_address mismatch' }));
            return;
          }
          const result = await messaging.relayMessage({
            sender_address: data.sender_address,
            receiver_address: data.receiver_address,
            encrypted_content: data.encrypted_content,
            message_type: 'text',
            signature: data.signature,
            sender_pubkey: data.sender_pubkey || '',
            timestamp: data.timestamp,
          });
          ws.send(JSON.stringify({ type: 'message_ack', data: result.message || result }));
        }
      } catch (error) {
        console.error('WS message error:', error);
        try {
          ws.send(JSON.stringify({ type: 'error', error: error.message || 'bad message' }));
        } catch (_) {}
      }
    });

    ws.on('close', () => {
      messaging.detachSocket(addr, ws);
    });
  });

  return wss;
}

module.exports = { attachMessagingWebSocket };

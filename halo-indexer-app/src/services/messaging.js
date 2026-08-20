const crypto = require('crypto');
const { getRedisClient } = require('./redis');

const MSG_TTL_SECONDS = 60 * 60 * 24 * 14; // 14 days
const PEER_TTL_SECONDS = 60 * 60 * 24 * 30;
const INBOX_MAX = 500;

/** @type {Map<string, Set<import('ws').WebSocket>>} */
const socketsByAddress = new Map();

function normalizeAddress(address) {
  return String(address || '').trim();
}

function attachSocket(address, ws) {
  const key = normalizeAddress(address);
  if (!key) return;
  if (!socketsByAddress.has(key)) socketsByAddress.set(key, new Set());
  socketsByAddress.get(key).add(ws);
}

function detachSocket(address, ws) {
  const key = normalizeAddress(address);
  const set = socketsByAddress.get(key);
  if (!set) return;
  set.delete(ws);
  if (set.size === 0) socketsByAddress.delete(key);
}

function isOnline(address) {
  const set = socketsByAddress.get(normalizeAddress(address));
  return !!(set && set.size > 0);
}

function pushToAddress(address, payload) {
  const set = socketsByAddress.get(normalizeAddress(address));
  if (!set || set.size === 0) return false;
  const raw = JSON.stringify(payload);
  let delivered = false;
  for (const ws of set) {
    if (ws.readyState === 1) {
      try {
        ws.send(raw);
        delivered = true;
      } catch (_) {
        /* ignore broken socket */
      }
    }
  }
  return delivered;
}

async function registerPeer({ address, publicKey, connectionInfo = {}, isOnline: online = true }) {
  const client = getRedisClient();
  const key = `halo:peer:${normalizeAddress(address)}`;
  const fields = {
    address: normalizeAddress(address),
    public_key: publicKey || '',
    is_online: online ? '1' : '0',
    connection_info: JSON.stringify(connectionInfo || {}),
    updated_at: new Date().toISOString(),
  };
  await client.hSet(key, fields);
  await client.expire(key, PEER_TTL_SECONDS);
  return fields;
}

async function getPeer(address) {
  const client = getRedisClient();
  const data = await client.hGetAll(`halo:peer:${normalizeAddress(address)}`);
  if (!data || !data.address) return null;
  return {
    address: data.address,
    public_key: data.public_key || '',
    is_online: data.is_online === '1' || isOnline(data.address),
    connection_info: (() => {
      try {
        return JSON.parse(data.connection_info || '{}');
      } catch {
        return {};
      }
    })(),
    updated_at: data.updated_at || null,
  };
}

async function listOnlinePeers(excludeAddress) {
  // Lightweight: only peers currently holding a WS are "online" for discovery.
  const exclude = normalizeAddress(excludeAddress);
  const online = [];
  for (const address of socketsByAddress.keys()) {
    if (address === exclude) continue;
    const peer = await getPeer(address);
    online.push(
      peer || {
        address,
        public_key: '',
        is_online: true,
        connection_info: { websocket: true },
      }
    );
  }
  return online;
}

async function storeMessage(message) {
  const client = getRedisClient();
  const id = crypto.randomUUID();
  const timestamp = message.timestamp || new Date().toISOString();
  const record = {
    id,
    sender_address: normalizeAddress(message.sender_address),
    receiver_address: normalizeAddress(message.receiver_address),
    encrypted_content: message.encrypted_content,
    message_type: message.message_type || 'text',
    signature: message.signature || '',
    sender_pubkey: message.sender_pubkey || '',
    timestamp,
  };
  const key = `halo:msg:${id}`;
  await client.hSet(key, record);
  await client.expire(key, MSG_TTL_SECONDS);

  const inboxKey = `halo:inbox:${record.receiver_address}`;
  await client.lPush(inboxKey, id);
  await client.lTrim(inboxKey, 0, INBOX_MAX - 1);
  await client.expire(inboxKey, MSG_TTL_SECONDS);

  // Also index under sender for conversation history pull
  const outboxKey = `halo:outbox:${record.sender_address}`;
  await client.lPush(outboxKey, id);
  await client.lTrim(outboxKey, 0, INBOX_MAX - 1);
  await client.expire(outboxKey, MSG_TTL_SECONDS);

  return record;
}

async function getMessagesForAddress(address, { limit = 100 } = {}) {
  const client = getRedisClient();
  const addr = normalizeAddress(address);
  const inboxIds = await client.lRange(`halo:inbox:${addr}`, 0, limit - 1);
  const outboxIds = await client.lRange(`halo:outbox:${addr}`, 0, limit - 1);
  const ids = [...new Set([...inboxIds, ...outboxIds])];
  const messages = [];
  for (const id of ids) {
    const data = await client.hGetAll(`halo:msg:${id}`);
    if (data && data.id) messages.push(data);
  }
  messages.sort((a, b) => String(a.timestamp).localeCompare(String(b.timestamp)));
  return messages.slice(-limit);
}

async function relayMessage(message) {
  const record = await storeMessage(message);
  const delivered = pushToAddress(record.receiver_address, {
    type: 'message',
    data: record,
  });
  // Also echo to sender sockets (multi-device)
  pushToAddress(record.sender_address, {
    type: 'message_ack',
    data: record,
  });
  return {
    success: true,
    message_id: record.id,
    delivered,
    timestamp: record.timestamp,
    message: record,
  };
}

module.exports = {
  attachSocket,
  detachSocket,
  isOnline,
  pushToAddress,
  registerPeer,
  getPeer,
  listOnlinePeers,
  storeMessage,
  getMessagesForAddress,
  relayMessage,
  normalizeAddress,
};

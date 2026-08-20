const fs = require('fs');
const path = require('path');
const fetch = require('node-fetch');

let cachedCharter = null;
let cachedEtag = null;
let lastLoadedAt = 0;

function getLocalFallbackPath() {
  return path.join(__dirname, '..', '..', 'charter', 'charter.json');
}

function normalizeCharter(obj) {
  // Minimal validation/normalization
  if (!obj || typeof obj !== 'object') return null;
  if (!Array.isArray(obj.categories)) obj.categories = [];
  if (!obj.enforcement) obj.enforcement = { default: 'hard_block', byCategory: {} };
  return obj;
}

async function fetchRemoteCharter(url, logger) {
  const headers = {};
  if (cachedEtag) headers['If-None-Match'] = cachedEtag;
  const res = await fetch(url, { headers, cache: 'no-store' });
  if (res.status === 304) return { unchanged: true };
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const etag = res.headers.get('etag') || res.headers.get('ETag');
  const text = await res.text();
  return { etag, body: text };
}

async function loadCharter(logger = console) {
  const src = process.env.CHARTER_SOURCE_URL;
  try {
    if (src && src.startsWith('http')) {
      try {
        const r = await fetchRemoteCharter(src, logger);
        if (r.unchanged) {
          return cachedCharter;
        }
        const normalized = normalizeCharter(typeof r.body === 'string' ? JSON.parse(r.body) : r.body);
        if (normalized) {
          cachedCharter = normalized;
          cachedEtag = r.etag || null;
          lastLoadedAt = Date.now();
          return cachedCharter;
        }
      } catch (e) {
        logger.warn('Charter remote fetch failed; will fallback to local', e?.message);
      }
    }
    // Local fallback
    const p = getLocalFallbackPath();
    if (fs.existsSync(p)) {
      const raw = fs.readFileSync(p, 'utf8');
      const normalized = normalizeCharter(JSON.parse(raw));
      if (normalized) {
        cachedCharter = normalized;
        lastLoadedAt = Date.now();
        return cachedCharter;
      }
    }
  } catch (e) {
    logger.error('Charter load error', e);
  }
  return cachedCharter;
}

function getCharterSync() {
  return cachedCharter;
}

function startCharterAutoRefresh(logger = console) {
  const intervalMs = Math.max(10, parseInt(process.env.CHARTER_REFRESH_SECONDS || '90', 10)) * 1000;
  // Initial load
  loadCharter(logger);
  setInterval(() => loadCharter(logger), intervalMs).unref?.();
}

module.exports = {
  loadCharter,
  getCharterSync,
  startCharterAutoRefresh
};



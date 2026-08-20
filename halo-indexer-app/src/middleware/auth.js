const crypto = require('crypto');

const JWT_SECRET = process.env.JWT_SECRET || 'halo-jwt-secret-change-in-production';

function verifyJWT(token) {
  if (!token || typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [encodedHeader, encodedPayload, signature] = parts;
  const expected = crypto
    .createHmac('sha256', JWT_SECRET)
    .update(`${encodedHeader}.${encodedPayload}`)
    .digest('base64url');
  const a = Buffer.from(signature);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  let payload;
  try {
    payload = JSON.parse(Buffer.from(encodedPayload, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
  const now = Math.floor(Date.now() / 1000);
  if (payload.exp && now > payload.exp) return null;
  if (!payload.address) return null;
  return payload;
}

function requireHaloAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    return res.status(401).json({ error: 'Missing Bearer token' });
  }
  const payload = verifyJWT(match[1].trim());
  if (!payload) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
  req.haloUser = {
    address: payload.address,
    bundleId: payload.bundleId || null,
  };
  next();
}

function verifyJWTFromQueryOrHeader(req) {
  const header = req.headers.authorization || '';
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (match) return verifyJWT(match[1].trim());
  if (req.query && req.query.token) return verifyJWT(String(req.query.token));
  return null;
}

module.exports = {
  verifyJWT,
  requireHaloAuth,
  verifyJWTFromQueryOrHeader,
  JWT_SECRET,
};

# Signature Verification Issue

## Problem

**Error:** `❌ HaloAPIService.verify HTTP 400: {"error":"Signature verification failed"}`

**Status:**
- ✅ Challenge request works (200 OK)
- ✅ Signature is created (88 bytes Base64 = 64 bytes raw)
- ✅ Public key is compressed (66 hex chars = 33 bytes)
- ❌ Signature verification fails on server

## Server Logs Analysis

From server logs:
```
warn: Signature did not verify against message hash LASKO|80252e708eff0de608e269d950a062b2|120|com.telestai.Zeroa
Verify debug: {
  msg: "LASKO|80252e708eff0de608e269d950a062b2|120|com.telestai.Zeroa",
  sha256: "a000e57e970369cda9fa13e28b01d08614a52a6f13aef4eb3f131b7966bccb3c",
  parseMode: "rs64",
  sigLen: 64,
  pubkeyPrefix: "0320579f181cb534...",
  pubkeyHexLen: 66
}
```

## Current Implementation

### iOS App (Zeroa)
1. Message: `LASKO|<nonce>|<ttlSeconds>|<bundleId>`
2. Hash: SHA256 of message (UTF-8)
3. Sign: secp256k1 signature of hash
4. Format: 64-byte r||s, Base64 encoded
5. Public Key: Compressed (33 bytes, 66 hex chars)

### Server
1. Message: `LASKO|<nonce>|<ttlSeconds>|<bundleId>` (from challenge)
2. Hash: SHA256 of message
3. Verify: elliptic.ec verify(hash, signature)
4. Parse: 64-byte r||s from Base64
5. Public Key: Compressed (33 bytes)

## Potential Issues

1. **Signature Format Mismatch**
   - iOS might be using a different signature format
   - Server expects r||s (64 bytes)
   - Need to verify iOS is creating correct format

2. **Message Encoding**
   - UTF-8 encoding might differ
   - Need to ensure exact byte match

3. **Elliptic Curve Library Differences**
   - iOS uses secp256k1 library
   - Server uses elliptic.js
   - Might have different verification logic

4. **Recovery ID**
   - Some libraries include recovery ID
   - Server expects raw r||s

## Next Steps

1. Add debug logging to see exact signature bytes
2. Test signature verification locally
3. Compare signature format between iOS and server expectations
4. Check if recovery ID is needed


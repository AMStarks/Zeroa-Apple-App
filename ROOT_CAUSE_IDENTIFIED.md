# ROOT CAUSE IDENTIFIED: Byte Order Mismatch

## Critical Discovery

**The iOS secp256k1 library returns signatures in LITTLE-ENDIAN byte order, but elliptic.js expects BIG-ENDIAN!**

### Test Results

**Server-side test:**
```javascript
// iOS signature (little-endian)
const rHex = 'f4b749acf59021e422d295806dbe6a21b7724af59e6afc008765720eeb37f774';
const sHex = '8f1bd7e80d78c4ba02444870d4e5fbec45607417188ac1ea54ce5b6938863232';

// Original (big-endian interpretation): false ❌
// Reversed (little-endian interpretation): true ✅
```

**Verification:**
- ✅ When bytes are reversed (little-endian → big-endian), verification succeeds!
- ❌ When bytes are used as-is (interpreted as big-endian), verification fails

## Root Cause

**iOS Library:** `GigaBitcoin/secp256k1.swift` (version 0.21.1)
- Returns signatures in **little-endian** byte order via `signature.dataRepresentation`

**Server Library:** `elliptic.js` (version 6.5.4)
- Expects signatures in **big-endian** byte order

## The Fix

**Location:** `Zeroa/CryptoService.swift` - `signMessageBase64()` function

**Change Required:**
Reverse the signature bytes (r and s) before encoding to Base64:

```swift
let signature = try privateKey.signature(for: digest)
let sigRaw = signature.dataRepresentation // 64 bytes r||s (little-endian)

// Reverse bytes to convert little-endian to big-endian
let r = sigRaw.prefix(32).reversed()
let s = sigRaw.suffix(32).reversed()
var sigBigEndian = Data()
sigBigEndian.append(contentsOf: r)
sigBigEndian.append(contentsOf: s)

// Now encode as Base64
let sigBase64 = sigBigEndian.base64EncodedString()
```

## Why This Happens

The iOS secp256k1 library (based on the C library) uses little-endian byte order internally, which is common for C libraries. However, most JavaScript/Node.js libraries (like elliptic.js) expect big-endian, which is the standard network byte order.

## Impact

- **All signatures created by iOS are in little-endian**
- **Server expects big-endian**
- **This causes 100% verification failure rate**

## Solution

Reverse the r and s components of the signature before sending to the server.


# Server Issues Found

## Issue 1: bs58 API Mismatch

**Problem:** The bs58 library (v6.0.0) uses ES modules with a default export, but the server code is using `bs58.encode()` which doesn't exist.

**Current Code:**
```javascript
const bs58 = require('bs58');
return bs58.encode(full);  // ❌ bs58.encode is not a function
```

**Actual API:**
```javascript
const bs58 = require('bs58');
// bs58 has { default: { encode: function, decode: function } }
// Should use: bs58.default.encode() or bs58.encode() if it's the default export
```

**Impact:** This causes the "Failed to derive address from provided pubkey" warning, but it's caught and doesn't block verification. However, it might be masking the real issue.

**Fix:** Update the server code to use the correct bs58 API.

## Issue 2: Signature Verification Failing

**Problem:** The signature (r, s) doesn't verify against the hash with the given public key.

**Test Results:**
- ✅ Hash matches: `8bef8d04a1d9992dd9df47e329bee9c5b72429297282a718418d08fb93f8e4ee`
- ✅ Public key is valid: `0320579f181cb53428695247bfbe266ccb7b0bd4d66130135fb3b82457c1752870`
- ✅ Signature format is correct: 64-byte r||s
- ✅ r and s are within curve order
- ❌ `key.verify(hash, sig)` returns `false`

**Root Cause:** The signature created by iOS secp256k1 library doesn't verify with elliptic.js, even though all parameters appear correct.

**Possible Causes:**
1. **Private/Public Key Mismatch:** The private key used to sign doesn't match the public key being sent
2. **Library Incompatibility:** iOS secp256k1 and Node.js elliptic.js have different signature formats or verification logic
3. **Signature Creation Issue:** The iOS library might be creating signatures incorrectly

## Next Steps

1. **Fix bs58 API usage** - Update server code to use correct bs58 API
2. **Verify public key match** - Add test to confirm public key matches private key
3. **Test signature creation** - Verify iOS signature can be verified by iOS library itself
4. **Compare libraries** - Check if there's a known incompatibility between iOS secp256k1 and elliptic.js


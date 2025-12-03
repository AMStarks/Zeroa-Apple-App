# Signature Verification Root Cause Analysis

## Summary

**Status:** Signature verification is failing at the cryptographic level.

**What Works:**
- ✅ Hash matches perfectly (iOS and server compute identical SHA256)
- ✅ Public key format is correct (33 bytes compressed, 0x03 prefix)
- ✅ Signature format is correct (64-byte r||s)
- ✅ Canonical message matches exactly
- ✅ Public key can be loaded by elliptic.js

**What Fails:**
- ❌ `key.verify(hash, sig)` returns `false`
- ⚠️ Address derivation fails (warning, not blocking)

## Root Cause

The signature (r, s) values created by iOS secp256k1 library **do not verify** against the hash with the given public key using elliptic.js.

### Test Results

**Server-side test with exact iOS values:**
```javascript
const pubHex = '0320579f181cb53428695247bfbe266ccb7b0bd4d66130135fb3b82457c1752870';
const message = 'LASKO|52351f03532647ee60de46cfa54ec54c|120|com.telestai.Zeroa';
const hash = '8bef8d04a1d9992dd9df47e329bee9c5b72429297282a718418d08fb93f8e4ee';
const r = '6da32ce727c7a3a1072384c6ee6a79162bebf67c305bbeca58d288945d0ee20d';
const s = 'dcaffb0908a57fe435544e057807852098359b553fe120b56eac22f4fe0f2366';

// Result: key.verify(hash, {r, s}) = false
```

**Verification:**
- ✅ r and s are within curve order
- ✅ Public key is valid
- ✅ Hash matches
- ❌ Signature doesn't verify

## Possible Causes

1. **Private/Public Key Mismatch**
   - The private key used to sign doesn't match the public key being sent
   - Both are derived from the same keychain key, so they should match
   - **Need to verify:** Does `getCompressedPublicKeyHex()` return the same key that corresponds to the private key used in `signMessageBase64()`?

2. **Library Compatibility Issue**
   - iOS secp256k1 library might create signatures in a format that elliptic.js doesn't accept
   - Even though format looks correct (64-byte r||s), the actual signature values might be incompatible

3. **Signature Normalization**
   - s value is HIGH (needs normalization: s > curve_order/2)
   - But even after normalization, verification still fails
   - This suggests normalization is not the issue

## Address Derivation Error

**Error:** "Failed to derive address from provided pubkey"

This is a **warning**, not blocking. The address derivation function should work with a 33-byte compressed public key. Need to check if there's an exception being thrown that's being caught.

## Next Steps

1. **Verify Public Key Match:**
   - Add code to verify that the public key sent to server actually corresponds to the private key used for signing
   - Test: Derive public key from private key on server and compare

2. **Check iOS secp256k1 Library:**
   - Verify that `signature(for: digest)` creates a signature that can be verified by the same library
   - Test: Create signature on iOS, then verify it on iOS using the same library

3. **Test with Known Key Pair:**
   - Create a test with a known private/public key pair
   - Sign on iOS, verify on server
   - This will isolate whether it's a key mismatch or library issue

4. **Check Address Derivation:**
   - Fix the address derivation error (might reveal the real issue)
   - Verify the public key format is exactly what's expected


# Signature Key Mismatch - Root Cause Found

## Critical Discovery

**The signature was NOT created with the public key being sent to the server.**

### Evidence

**Server-side signature recovery test:**
```javascript
// Attempting to recover public key from signature...
Recovered pubkey (recovery ID 0): 03e1ae199764e21f97cb7f49411adaa6ebf628a6f00c8745ef1a854f2201944d74
Recovered pubkey (recovery ID 1): 025878e65f70df0fcb31fc36880cb8cf20572a441dbbffcdd825a6406712f26d7c
```

**Public key being sent from iOS:**
```
0320579f181cb53428695247bfbe266ccb7b0bd4d66130135fb3b82457c1752870
```

**Result:** None of the recovered public keys match the one being sent!

### What This Means

The private key used to create the signature does **NOT** match the public key being sent to the server. This is why verification fails.

### Possible Causes

1. **Different Private Keys:**
   - `signMessageBase64()` uses one private key from keychain
   - `getCompressedPublicKeyHex()` uses a different private key from keychain
   - Or the keychain has multiple keys and they're being mixed up

2. **Key Derivation Issue:**
   - The public key derivation might be incorrect
   - Or the private key format might be wrong

3. **Keychain Corruption:**
   - The private key might be getting corrupted between calls
   - Or there might be encoding issues

### Next Steps

1. **Add verification logging** to compare:
   - Public key derived during signing (from private key used to sign)
   - Public key sent to server (from `getCompressedPublicKeyHex()`)
   - They MUST match!

2. **Check keychain:**
   - Verify there's only one `wallet_private_key` in the keychain
   - Check if the key is being modified between calls

3. **Test with known key pair:**
   - Create a test that uses the same private key for both signing and public key derivation
   - Verify they produce matching results

## Fix Applied

Added logging to `CryptoService.signMessageBase64()` to show the public key derived from the private key used for signing. This will be compared with the public key from `getCompressedPublicKeyHex()` to identify the mismatch.


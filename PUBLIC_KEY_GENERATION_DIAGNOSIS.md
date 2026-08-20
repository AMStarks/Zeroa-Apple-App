# Public Key Generation Diagnosis

## Summary

I've traced through the entire public key generation flow on both iOS and server sides. Here's what I found:

## iOS Public Key Generation

### Source: Keychain
- **Key:** `"wallet_private_key"`
- **Format:** Hex string (64 hex chars = 32 bytes)
- **Storage:** `KeychainService.save(key: "wallet_private_key", value: privateKey.hexString)`
- **Retrieval:** `keychain.read(key: "wallet_private_key")` → Returns hex string

### Two Functions That Generate Public Keys

#### 1. `signMessageBase64()` - Used for Signing
**Location:** `Zeroa/CryptoService.swift:45-155`

**Flow:**
```
keychain.read("wallet_private_key")
  → hex string
  → Data(hexString: privHex)
  → Secp.Signing.PrivateKey(dataRepresentation: privKeyData)
  → privateKey.publicKey.dataRepresentation
  → Compress if needed (65 → 33 bytes)
  → Convert to hex
  → Use this private key to SIGN
```

#### 2. `getCompressedPublicKeyHex()` - Used for Server
**Location:** `Zeroa/CryptoService.swift:157-213`

**Flow:**
```
keychain.read("wallet_private_key")
  → hex string
  → Data(hexString: privHex)
  → Secp.Signing.PrivateKey(dataRepresentation: privKeyData)
  → privateKey.publicKey.dataRepresentation
  → Compress if needed (65 → 33 bytes)
  → Convert to hex
  → Return to send to server
```

### Critical Finding

**Both functions:**
- ✅ Read from the **same keychain key**
- ✅ Use the **same keychain service**
- ✅ Use the **same conversion logic** (hex → Data)
- ✅ Use the **same library** (secp256k1)
- ✅ Use the **same derivation** (`privateKey.publicKey.dataRepresentation`)
- ✅ Use the **same compression logic** (now fixed to match exactly)

**They should produce IDENTICAL public keys!**

## Bug Found and Fixed

### Issue
The compression logic in `signMessageBase64()` was incomplete - it didn't check if the public key was already compressed (33 bytes) before trying to compress it.

### Fix
Updated `signMessageBase64()` to use **EXACT same logic** as `getCompressedPublicKeyHex()`:
1. Check if already compressed (33 bytes, prefix 0x02/0x03) → use as-is
2. Check if uncompressed (65 bytes, prefix 0x04) → compress it
3. Unknown format → use as-is

## Server-Side Public Key Usage

### Server Verification Flow
**Location:** `/opt/halo/halo-indexer-app/src/services/auth.js`

**Flow:**
```
Receive pubkeyCompressedHex from iOS
  → Normalize (remove 0x prefix, lowercase)
  → ec.keyFromPublic(pubHex, 'hex')
  → key.verify(hash, signature)
```

### Server Signature Recovery Test
When we tried to recover the public key from the signature:
- Recovered pubkey (ID 0): `03e1ae199764e21f...`
- Recovered pubkey (ID 1): `025878e65f70df0f...`
- Sent pubkey: `0320579f181cb534...`

**None match!** This confirms the signature was NOT created with the public key being sent.

## Root Cause Hypothesis

Since both iOS functions use the same source and logic, the most likely causes are:

1. **Keychain Read Inconsistency** (Unlikely)
   - The keychain value might change between reads
   - Both reads happen in quick succession, so unlikely

2. **Library Behavior** (Possible)
   - The secp256k1 library might return different public key formats inconsistently
   - But both functions now handle compression identically

3. **Encoding Issue** (Possible)
   - Hex encoding/decoding might introduce errors
   - Need to verify the hex conversion is correct

4. **Private Key Mismatch** (Most Likely)
   - The private key in keychain might not match what was used to create the address
   - Or there might be multiple private keys stored

## Next Steps

1. **Rebuild app** with the fix
2. **Check logs** - Compare the two public keys:
   - From `signMessageBase64()`: "Public key derived from private key (for verification)"
   - From `getCompressedPublicKeyHex()`: "Public key (hex)"
3. **If they match** - The issue is elsewhere (server-side or signature format)
4. **If they don't match** - Investigate keychain read consistency or library behavior

## Files Modified

1. **`Zeroa/CryptoService.swift`**
   - Fixed compression logic in `signMessageBase64()` to match `getCompressedPublicKeyHex()` exactly
   - Added public key logging for comparison

2. **`Zeroa/HaloService.swift`**
   - Added warning to compare public keys

3. **Server: `/opt/halo/halo-indexer-app/src/services/auth.js`**
   - Fixed bs58 API usage (`bs58.encode` → `bs58.default.encode`)


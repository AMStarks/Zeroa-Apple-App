# Signature Verification Diagnostics Guide

## Overview

Comprehensive diagnostic logging has been added to identify the exact cause of signature verification failures. The logs will show:

## Diagnostic Sections

### 1. HALO TOKEN VERIFICATION DIAGNOSTICS
Shows the complete verification request:
- Address being verified
- Bundle ID
- Nonce from challenge
- TTL
- Canonical message (exact string)
- Canonical message bytes (UTF-8 hex)

### 2. SIGNATURE DIAGNOSTICS
Shows signature creation details:
- **Message**: The exact canonical message being signed
- **Message bytes (UTF-8 hex)**: Raw bytes of the message
- **SHA256 hash (hex)**: The hash that's being signed (compare with server logs)
- **Private key length**: Should be 32 bytes
- **Signature raw length**: Should be 64 bytes
- **Signature (hex, full)**: Complete signature in hex
- **r (32 bytes hex)**: First 32 bytes (r component)
- **s (32 bytes hex)**: Last 32 bytes (s component)
- **s value check**: Shows if s needs normalization (should be <= curve_order/2)
- **Signature (Base64)**: Final Base64-encoded signature sent to server

### 3. PUBLIC KEY DIAGNOSTICS
Shows public key format and conversion:
- **Public key raw length**: Should be 33 (compressed) or 65 (uncompressed)
- **Public key first byte**: 0x02 or 0x03 (compressed), 0x04 (uncompressed)
- **Public key (hex, full)**: Complete public key
- **Format detection**: Shows if key is COMPRESSED, UNCOMPRESSED, or UNKNOWN
- **Compression details**: If uncompressed, shows x/y coordinates and compression process
- **Final public key (hex)**: What's sent to server (should be 66 hex chars = 33 bytes)

### 4. SENDING TO SERVER
Shows exactly what's being sent:
- Address
- Bundle ID
- Nonce
- Signature (Base64)
- Signature length
- Public key (hex)
- Public key length

### 5. SERVER VERIFICATION RESPONSE
Shows server's response:
- HTTP Status code
- Response body (error message)

## What to Compare

When you get the logs, compare:

1. **SHA256 Hash**: 
   - iOS: From "SIGNATURE DIAGNOSTICS" → "SHA256 hash (hex)"
   - Server: From server logs → "sha256" field
   - **Should match exactly**

2. **Canonical Message**:
   - iOS: From "HALO TOKEN VERIFICATION DIAGNOSTICS" → "Canonical message"
   - Server: From server logs → "msg" field
   - **Should match exactly**

3. **Public Key Format**:
   - iOS: From "PUBLIC KEY DIAGNOSTICS" → Check if COMPRESSED or UNCOMPRESSED
   - Server: From server logs → "pubkeyHexLen" should be 66 (33 bytes)
   - **Should be COMPRESSED (33 bytes)**

4. **Signature Format**:
   - iOS: From "SIGNATURE DIAGNOSTICS" → Should be "64-byte r||s (correct)"
   - Server: From server logs → "parseMode" should be "rs64", "sigLen" should be 64
   - **Should match**

5. **Signature Values**:
   - iOS: r and s values from "SIGNATURE DIAGNOSTICS"
   - Server: Parsed r and s (check server logs for signature parsing)
   - **Should match**

## Common Issues to Check

1. **Public Key Uncompressed**: If iOS shows "UNCOMPRESSED (65 bytes)", the compression code will fix it
2. **Signature Format Wrong**: If signature is not 64 bytes, there's a format issue
3. **Hash Mismatch**: If SHA256 hashes don't match, message encoding is wrong
4. **s Value Too High**: If s > curve_order/2, signature needs normalization (low-s)

## Next Steps

1. Rebuild the app with these diagnostics
2. Run the app and attempt token verification
3. Copy the diagnostic logs (look for sections with ═══ separators)
4. Compare with server logs to identify the mismatch


# Signature Hash Buffer Analysis

## ✅ What We Know

1. **Outputs sent to createrawtransaction:**
   - Tk5pU7M5HDURs9tkEtSeDKeWMFaFRrJrrP: 8999.98192 TLS (899998192000 satoshis)
   - TqWZPtjer7dQfgHWSveMfb2XDmbAm91ePb: 1000.0 TLS (100000000000 satoshis)

2. **Parsed transaction (CORRECT):**
   - Output 0: 899998192000 satoshis (8999.98192 TLS) ✅
   - Output 1: 100000000000 satoshis (1000.0 TLS) ✅

3. **Signature hash buffer (WRONG):**
   - Output 0: `8091128cd1000000` = 3,520,000,000 satoshis (35.2 TLS) ❌
   - Output 1: `00e8764817000000` = 24,000,000 satoshis (0.24 TLS) ❌

## 🔍 The Problem

The signature hash buffer shows DIFFERENT output values than the parsed transaction, even though we're using the same transaction (`txForHash = transaction`).

## 🎯 Root Cause

Looking at the signature hash buffer hex:
```
8091128cd1000000 = 0x00000000d18c1280 = 3,520,000,000 satoshis
```

But the parsed transaction shows:
```
899998192000 satoshis = 0x000000d18c1280 (in hex, but needs 8 bytes)
```

Wait - let me check the actual hex values in the buffer more carefully. The buffer shows:
- `8091128cd1000000` - this is 8 bytes, little-endian
- Reading as little-endian: `0x00000000d18c1280` = 3,520,000,000

But 899998192000 in hex is `0xd18c1280` (if we ignore the higher bytes), which matches the lower 4 bytes!

Actually, 899998192000 = 0x000000d18c1280 in 8 bytes.

But the buffer shows `8091128cd1000000`. Let me reverse this (little-endian):
- `8091128cd1000000` reversed = `00000000d18c1280` = 3,520,000,000

Hmm, that's still wrong. Let me think...

Actually, I think I see it now. The buffer hex string might be showing the bytes in the wrong order, or there's an issue with how we're reading the values from the transaction when building the hash buffer.

The issue is that when we serialize the outputs for the signature hash, we're using `txForHash.outputs`, which should be the same as `transaction.outputs`. But the values are different!

This suggests that either:
1. We're modifying the transaction outputs somewhere
2. We're reading from the wrong transaction
3. There's a bug in how we serialize outputs for the hash


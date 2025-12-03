# Next Steps Report

## ✅ Completed

1. **Router Configuration:** Already configured ✅
   - Port 2222 → 192.168.0.121:22 (SSH)
   - Port 80 → 192.168.0.121:80 (HTTP)
   - Port 443 → 192.168.0.121:443 (HTTPS)

2. **Firewall Configuration:** ✅
   - UFW configured with ports 22/2222 open
   - SSH service running

3. **Daemon Code Review:** ✅
   - Reviewed `signrawtransaction` implementation
   - Identified keystore lookup issue
   - Verified scriptPubKey hash matching works

## 🔍 Root Cause

The RPC's `signrawtransaction` is failing because:
- Keystore lookup (`GetKey(CKeyID)`) fails even though hashes match
- This suggests a parameter encoding or public key format mismatch
- Despite multiple attempts (WIF version bytes, compression flags), RPC signing still fails

## 💡 Solution: Client-Side Signing

**Implement full client-side transaction signing** to bypass RPC entirely.

### What This Requires:

1. **Transaction Parsing:**
   - Parse raw transaction hex
   - Extract inputs, outputs, locktime, version

2. **SignatureHash Computation:**
   - Implement Bitcoin's SignatureHash algorithm
   - Handle SIGHASH flags (ALL, NONE, SINGLE, ANYONECANPAY)
   - Compute hash for each input to sign

3. **Signing:**
   - Sign each SignatureHash with private key
   - Create DER-encoded signature
   - Append SIGHASH byte

4. **ScriptSig Creation:**
   - For P2PKH: `<signature> <public_key>`
   - Insert into transaction inputs

5. **Transaction Serialization:**
   - Serialize signed transaction to hex
   - Send to RPC for broadcast only

### Complexity: **HIGH**

This is a significant implementation (~500-1000 lines of code) requiring:
- Deep understanding of Bitcoin transaction format
- SignatureHash algorithm implementation
- Script encoding/decoding
- Transaction serialization

## 🎯 Recommendation

**Option 1: Implement Client-Side Signing (Recommended)**
- Most reliable solution
- More secure (keys never leave device)
- Bypasses all RPC issues
- **Time:** 2-4 hours of implementation + testing

**Option 2: Debug RPC Further**
- Try one more approach: Import key first, then sign
- Check if there's a parameter encoding issue
- **Time:** 1-2 hours, may not work

**Option 3: Use Existing Library**
- Look for Swift Bitcoin transaction signing library
- May not exist or may not support Telestai

## 📋 Next Steps

1. **Decide on approach** (I recommend Option 1)
2. **Implement client-side signing** if chosen
3. **Test thoroughly** with real transactions
4. **Verify external SSH** after router restart

## ⚠️ Note on External SSH

External SSH (port 2222) may need:
- Router restart to apply port forwarding
- ISP may be blocking port 2222
- Can test from external network to verify

For now, local access is sufficient to proceed with implementation.


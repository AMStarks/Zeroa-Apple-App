# Signing Error Deep Dive Analysis

**Date:** 2025-01-27  
**Error:** "Unable to sign input, invalid stack size (possibly missing key)"  
**Status:** Critical Issue - Root Cause Analysis

---

## 🔍 **Research Findings**

### **1. Error Meaning**
The error "Unable to sign input, invalid stack size (possibly missing key)" typically indicates:
- The RPC cannot match the private key to the scriptPubKey's public key hash
- The private key's derived address doesn't match the UTXO's address
- Network mismatch between WIF version byte and the blockchain network

### **2. Common Causes (from Bitcoin StackExchange & research)**

1. **Network Mismatch** ⚠️ **MOST LIKELY**
   - Using a WIF with version byte 0x80 (Bitcoin mainnet) on a different network
   - Each network has distinct WIF version byte prefixes
   - The RPC derives an address from the WIF, and if the version byte is wrong, it derives the wrong address

2. **Private Key/Address Mismatch**
   - The private key doesn't correspond to the address in the UTXO
   - Even if imported, the RPC might not associate it correctly

3. **Incomplete prevTxs Data**
   - Missing or incorrect scriptPubKey or amount
   - We're providing this correctly, so less likely

4. **Non-Standard Scripts**
   - P2PKH should be standard, so unlikely

---

## 🚨 **CRITICAL DISCOVERY**

### **Version Byte Mismatch**

**Telestai Address Version Byte:** `0x42` (confirmed in `WalletService.swift:286`)  
**Current WIF Version Byte:** `0x80` (Bitcoin mainnet standard)

**The Problem:**
- When we import a WIF with version byte `0x80`, the RPC might derive an address using Bitcoin's address version byte (0x00)
- But Telestai uses address version byte `0x42`
- This mismatch causes the RPC to think the private key doesn't match the scriptPubKey

**Evidence:**
- Our code derives addresses with version byte `0x42` (line 286 in WalletService.swift)
- We're generating WIF with version byte `0x80` (line 677 in TLSBlockchainService.swift)
- The RPC likely derives addresses from WIF using the network's address version byte
- If the WIF version byte doesn't match the network, the derived address won't match

---

## 🔬 **What We've Verified**

✅ **Correct:**
- Private key derivation (address verification passes)
- scriptPubKey format (P2PKH, correct hex)
- Amount format (numeric, correct)
- prevTxs structure (txid, vout, scriptPubKey, amount all provided)
- Key import succeeds
- WIF format is correct (Base58, correct length, correct structure)

❌ **Unverified:**
- WIF version byte matches Telestai network
- RPC's derived address from imported WIF matches our expected address
- Network identifier in RPC matches our assumptions

---

## 💡 **What We Might Have Missed**

### **1. WIF Version Byte Must Match Network**

**Hypothesis:** Telestai's RPC expects WIF version byte to match the network identifier, not just be a standard Bitcoin value.

**Test Needed:**
- Import a WIF with version byte `0x42` (matching Telestai address version)
- Check what address the RPC derives from it
- Compare to our expected address

### **2. RPC Address Derivation**

**Hypothesis:** When the RPC imports a WIF, it derives an address using the network's address version byte. If the WIF version byte doesn't match the network, it might:
- Reject the WIF (we see "Invalid private key" for 0x42, 0xB0, 0xEF)
- Derive a different address than expected
- Fail to match the key to the scriptPubKey

### **3. Network Configuration**

**Hypothesis:** The `telestaid` RPC might be configured for a specific network, and our WIF version byte doesn't match that network's expected format.

**What to Check:**
- Telestai daemon source code for WIF version byte
- Network configuration in `telestaid` config file
- Whether Telestai uses a custom WIF version byte

---

## 🎯 **Recommended Next Steps**

### **Priority 1: Determine Correct WIF Version Byte**

1. **Check Telestai Source Code**
   - Search for WIF version byte definition
   - Check network configuration
   - Look for address/WIF version byte mapping

2. **Test with Known Good WIF**
   - If we can get a WIF from `dumpprivkey` for an address that works
   - Compare its version byte to what we're generating
   - This would definitively show the correct version byte

3. **Try WIF Version Byte 0x42**
   - Since Telestai uses address version byte 0x42, try WIF version byte 0x42
   - Some networks use the same version byte for addresses and WIF
   - We already tried this but got "Invalid private key" - might need different approach

### **Priority 2: Verify RPC Address Derivation**

1. **After Importing WIF, Check Derived Address**
   - Use `getaddressesbyaccount` or `listaddressgroupings` after import
   - Compare to our expected address
   - If mismatch, that's the root cause

2. **Test Address Derivation**
   - Import WIF with different version bytes
   - Check what address the RPC derives
   - Find which version byte gives the correct address

### **Priority 3: Alternative Approach**

If WIF version byte can't be determined:
1. **Use `signrawtransactionwithwallet`** instead of `signrawtransaction`
   - This uses wallet keys only (no keys in call)
   - Requires keys to be imported first
   - Might work if import succeeds but call format is wrong

2. **Client-Side Signing**
   - Sign the transaction entirely on the client
   - Don't rely on RPC for signing
   - More secure, but requires full transaction construction

---

## 📋 **Action Items**

1. ✅ Research error meaning and common causes
2. ⏳ Check Telestai source code for WIF version byte
3. ⏳ Test RPC address derivation after WIF import
4. ⏳ Try alternative signing methods
5. ⏳ Verify network configuration matches our assumptions

---

## 🔗 **References**

- Bitcoin StackExchange: Network mismatch issues
- Bitcoin StackExchange: WIF version byte requirements
- Bitcoin Core RPC documentation: signrawtransaction parameters
- Research: "Unable to sign input, invalid stack size" error causes

---

## 💭 **Key Insight**

The most likely issue is that **the WIF version byte (0x80) doesn't match Telestai's network identifier**. When the RPC imports the WIF, it derives an address that doesn't match our expected address (which uses version byte 0x42), causing the signing to fail with "invalid stack size" because the key doesn't match the scriptPubKey.

**Next Critical Test:** Verify what address the RPC derives from an imported WIF, and compare it to our expected address. If they don't match, we've found the root cause.


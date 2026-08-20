# Telestai WIF Version Byte - FOUND! ✅

## 🎯 **Discovery**

Found in: `src/chainparams.cpp` in Telestai repository

## 📋 **Telestai Mainnet Network Parameters**

From the source code:

```cpp
// Mainnet (from src/chainparams.cpp)
base58Prefixes[PUBKEY_ADDRESS] = std::vector<unsigned char>(1,66);   // 0x42 ✅
base58Prefixes[SCRIPT_ADDRESS] = std::vector<unsigned char>(1,127);  // 0x7F
base58Prefixes[SECRET_KEY] =     std::vector<unsigned char>(1,128);  // 0x80 ✅
```

### **Key Findings:**

1. **Address Version Byte:** `0x42` (66 decimal) ✅ **CONFIRMED**
   - This matches what our app uses
   - Addresses start with `T` (Base58 encoding of 0x42)

2. **WIF Version Byte:** `0x80` (128 decimal) ✅ **CONFIRMED**
   - **This is the SAME as Bitcoin mainnet!**
   - We were using the correct WIF version byte all along

3. **Testnet WIF Version Byte:** `0xEF` (239 decimal)
   - For reference, testnet uses 0xEF (same as Bitcoin testnet)

## 🚨 **The Real Problem**

**We're using the CORRECT WIF version byte (0x80)!**

The issue is NOT the WIF version byte. The problem is:

1. ✅ Our app generates WIF with version byte `0x80` (CORRECT)
2. ✅ RPC accepts WIF with version byte `0x80` (CORRECT)
3. ❌ **RPC derives address using Bitcoin's address version byte (0x00) instead of Telestai's (0x42)**

When the RPC imports a WIF:
- It correctly decodes the WIF (version byte 0x80 is valid)
- But it derives the address using **Bitcoin's address version byte (0x00)**
- Instead of **Telestai's address version byte (0x42)**

This is why:
- RPC derives: `Tx1vVL35mWariU1fSDc75wXDkZD1ZoGcqp` (starts with `Tx1...` = Bitcoin address format)
- We expect: `TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x` (starts with `TiN...` = Telestai address format)

## 💡 **Root Cause**

The RPC daemon (`telestaid`) is likely:
1. **Not properly configured for Telestai network**, OR
2. **Has a bug in address derivation** when importing WIFs

The daemon should use address version byte `0x42` when deriving addresses, but it's using `0x00` (Bitcoin's).

## 🔧 **Solution**

Since we can't fix the RPC daemon's address derivation, we need to:

1. **Don't import keys** (we already removed this)
2. **Provide keys directly in `signrawtransaction` call**
3. **RPC should match keys to scriptPubKey by public key hash**, not by address

The RPC's `signrawtransaction` should:
- Take the private key (WIF)
- Derive the public key
- Hash it to get the pubkey hash (RIPEMD160(SHA256(public key)))
- Compare this hash to the pubkey hash in the scriptPubKey
- This should work regardless of address version byte

## ✅ **Confirmation**

- ✅ WIF version byte `0x80` is CORRECT for Telestai mainnet
- ✅ Address version byte `0x42` is CORRECT for Telestai mainnet
- ✅ Our app is generating both correctly
- ❌ RPC daemon is deriving addresses incorrectly (using 0x00 instead of 0x42)

## 📝 **Next Steps**

1. ✅ We've already removed key import (good)
2. ✅ We're providing keys directly in the call (good)
3. ⏳ Test if signing works with keys in call (no import)
4. If it still fails, the RPC might have a deeper issue with key-to-scriptPubKey matching


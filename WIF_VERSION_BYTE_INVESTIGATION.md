# WIF Version Byte Investigation

## 🎯 **The Core Question**

**Does the Telestai core wallet/daemon source code specify the WIF version byte?**

This is critical because:
- The RPC derives address `Tx1vVL35mWariU1fSDc75wXDkZD1ZoGcqp` from our WIF (version byte 0x80)
- We expect address `TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x` (uses version byte 0x42)
- This mismatch causes signing to fail

---

## 🔍 **What We Know**

### **Address Version Byte:**
- ✅ **Telestai uses:** `0x42` (confirmed in `WalletService.swift:286`)
- ✅ **Our app generates addresses with:** `0x42`
- ✅ **Addresses start with:** `T` (Base58 encoding of 0x42)

### **WIF Version Byte:**
- ❓ **Currently using:** `0x80` (Bitcoin mainnet standard)
- ❓ **Telestai might use:** Unknown - need to check source code
- ❌ **RPC rejects:** `0x42`, `0xB0`, `0xEF` (returns "Invalid private key")
- ⚠️ **RPC accepts:** `0x80` but derives wrong address

### **The Mismatch:**
```
Our App:
  Private Key → WIF (0x80) → Address (0x42) = TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x ✅

RPC Daemon:
  WIF (0x80) → Address (0x00?) = Tx1vVL35mWariU1fSDc75wXDkZD1ZoGcqp ❌
```

---

## 📋 **What to Check in Core Wallet/Daemon**

### **1. Source Code Location:**
- Telestai daemon source code (GitHub repository?)
- Look for WIF version byte definition
- Check `base58.h` or similar encoding files
- Check network parameters/constants

### **2. Key Files to Examine:**
- `src/base58.h` or `base58.cpp` - Base58 encoding implementation
- `src/chainparams.cpp` or `chainparams.h` - Network parameters
- `src/key.h` or `key.cpp` - Private key handling
- `src/wallet/wallet.cpp` - Wallet import/export functions

### **3. What to Look For:**
```cpp
// Example from Bitcoin Core:
static const unsigned char PRIVKEY_ADDRESS = 0x80;  // Mainnet WIF version byte
static const unsigned char PUBKEY_ADDRESS = 0x00;   // Mainnet address version byte

// Telestai might have:
static const unsigned char PRIVKEY_ADDRESS = 0x??;  // What value?
static const unsigned char PUBKEY_ADDRESS = 0x42;   // Confirmed
```

---

## 🤔 **iOS vs Core Wallet Differences**

### **Potential iOS-Specific Issues:**

1. **Library Differences:**
   - iOS uses Swift/CryptoKit
   - Core wallet might use OpenSSL or libsecp256k1
   - Different implementations might handle WIF differently

2. **Address Derivation:**
   - Our app: Derives address with version byte 0x42 ✅
   - RPC: Derives address with version byte 0x00 (Bitcoin) ❌
   - This suggests RPC is using Bitcoin's address version, not Telestai's

3. **WIF Handling:**
   - The RPC might be hardcoded to use Bitcoin's WIF version byte (0x80)
   - But then derive addresses using Bitcoin's address version byte (0x00)
   - This would explain why addresses don't match

---

## 💡 **Hypothesis**

**The RPC daemon might be:**
1. Accepting WIF with version byte 0x80 (Bitcoin standard)
2. But deriving addresses using Bitcoin's address version byte (0x00)
3. Instead of Telestai's address version byte (0x42)

**This would mean:**
- The WIF version byte might be correct (0x80)
- But the RPC's address derivation is wrong
- OR the RPC needs a different WIF version byte that matches Telestai's network

---

## 🔧 **Next Steps**

### **1. Check Telestai Source Code:**
```bash
# If you have access to Telestai daemon source:
grep -r "PRIVKEY_ADDRESS\|WIF\|0x80\|0x42" src/
grep -r "base58.*version\|version.*byte" src/
```

### **2. Check RPC Help:**
```bash
# On Optimus server:
curl -X POST http://127.0.0.1:8766 \
  -u rpc:rpc \
  -H 'Content-Type: application/json' \
  -d '{"method":"help","params":["importprivkey"],"id":1}'
```

### **3. Test with Known Good WIF:**
- If you have a working Telestai wallet
- Export a private key as WIF
- Check what version byte it uses
- Compare to what we're generating

### **4. Check Network Parameters:**
- Telestai daemon config file
- Network constants in source code
- Any documentation about WIF format

---

## 📝 **Questions to Answer**

1. **Does Telestai core wallet use WIF version byte 0x80?**
   - If yes, why does RPC derive wrong address?
   - If no, what version byte does it use?

2. **Is this iOS-specific?**
   - Does the core wallet work correctly?
   - Is the issue only in our iOS app?

3. **How does the RPC match keys to scriptPubKey?**
   - By address? (would fail with mismatch)
   - By public key hash? (should work regardless of WIF version byte)

---

## 🎯 **Current Status**

- ✅ **Confirmed:** Address mismatch (RPC derives `Tx1vVL35...` instead of `TiN9tR13...`)
- ❓ **Unknown:** Correct WIF version byte for Telestai
- ❓ **Unknown:** Whether core wallet has same issue
- ⏳ **Next:** Check Telestai source code or reference implementation

---

## 🔗 **Resources to Check**

1. Telestai daemon GitHub repository
2. Telestai documentation/wiki
3. Telestai core wallet (if separate from daemon)
4. Any Telestai wallet implementations (reference or otherwise)


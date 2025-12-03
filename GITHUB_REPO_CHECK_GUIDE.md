# Telestai GitHub Repository Check Guide

## 🎯 **Goal**
Find the WIF (Wallet Import Format) version byte used by Telestai in the source code.

## 📍 **Repository Location**
https://github.com/Telestai-Project/telestai

## 🔍 **Key Files to Check**

### **1. Network Parameters (Most Likely Location)**
- `src/chainparams.cpp` or `src/chainparams.h`
- Look for constants like:
  ```cpp
  static const unsigned char PRIVKEY_ADDRESS = 0x??;
  static const unsigned char PUBKEY_ADDRESS = 0x42;  // We know this is 0x42
  ```

### **2. Base58 Encoding**
- `src/base58.h` or `src/base58.cpp`
- May contain version byte definitions

### **3. Private Key Handling**
- `src/key.h` or `src/key.cpp`
- May contain WIF encoding/decoding logic

### **4. Wallet Functions**
- `src/wallet/wallet.cpp`
- Look for `importprivkey` or WIF-related functions

## 🔎 **What to Search For**

### **Search Terms:**
1. `PRIVKEY_ADDRESS` - Common Bitcoin Core constant name
2. `WIF` - Wallet Import Format
3. `0x80` - Bitcoin's WIF version byte (to see if Telestai uses same)
4. `0x42` - Telestai's address version byte (to see if WIF matches)
5. `base58` - Base58 encoding (where version bytes are used)

### **GitHub Search URLs:**
- https://github.com/Telestai-Project/telestai/search?q=PRIVKEY_ADDRESS
- https://github.com/Telestai-Project/telestai/search?q=WIF
- https://github.com/Telestai-Project/telestai/search?q=0x80
- https://github.com/Telestai-Project/telestai/search?q=chainparams

## 📋 **What We're Looking For**

### **Expected Pattern (from Bitcoin Core):**
```cpp
// In chainparams.cpp or similar:
class CMainParams : public CChainParams {
public:
    CMainParams() {
        base58Prefixes[PUBKEY_ADDRESS] = std::vector<unsigned char>(1,0x42);  // Telestai uses 0x42
        base58Prefixes[SCRIPT_ADDRESS] = std::vector<unsigned char>(1,0x??);
        base58Prefixes[SECRET_KEY] = std::vector<unsigned char>(1,0x??);      // This is WIF version byte!
        // ...
    }
};
```

### **Or in constants:**
```cpp
static const unsigned char PRIVKEY_ADDRESS = 0x80;  // Bitcoin uses 0x80
static const unsigned char PUBKEY_ADDRESS = 0x42;   // Telestai uses 0x42
```

## 🎯 **Expected Findings**

### **If Telestai Uses Bitcoin's WIF Version Byte (0x80):**
- This would explain why RPC accepts 0x80
- But RPC might be deriving addresses incorrectly
- Need to check if RPC uses correct address version byte

### **If Telestai Uses Different WIF Version Byte:**
- Might be 0x42 (matching address version byte)
- Or another value specific to Telestai
- This would explain why RPC rejects our WIF

## 🔧 **How to Check**

### **Option 1: Browse GitHub Online**
1. Go to https://github.com/Telestai-Project/telestai
2. Use GitHub's search (top of page)
3. Search for: `PRIVKEY_ADDRESS` or `WIF` or `0x80`
4. Check results in `src/chainparams.cpp` or similar files

### **Option 2: Clone Repository Locally**
```bash
cd /tmp  # or wherever you want
git clone https://github.com/Telestai-Project/telestai.git
cd telestai
grep -r "PRIVKEY_ADDRESS\|WIF\|0x80" src/
grep -r "SECRET_KEY\|base58Prefixes" src/chainparams*
```

### **Option 3: Check on Optimus Server**
If you have access to Optimus and the daemon source is there:
```bash
ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121
# Then search for WIF version byte in daemon source
```

## 📝 **What to Report Back**

1. **WIF Version Byte Value:**
   - What value does Telestai use? (0x80, 0x42, or something else?)

2. **Location in Code:**
   - Which file contains the definition?
   - What's the constant/variable name?

3. **Address Version Byte:**
   - Confirm it's 0x42 (we already know this, but good to verify)

4. **Any Comments:**
   - Does the code have comments explaining the choice?

## 🚨 **If Not Found**

If we can't find it in the repository:
1. Check if it's in a different branch
2. Check release notes or documentation
3. Check Optimus server for daemon source code
4. Test with `dumpprivkey` RPC (if we can get a key from the wallet)


# Solution Analysis: "Unable to sign input, invalid stack size" Error

## 🔍 **What the Telestai Core Wallet Code Reveals**

From examining `src/rpc/rawtransaction.cpp`:

### **How `signrawtransaction` Works:**

1. **Private Keys Handling:**
   ```cpp
   CTelestaiSecret vchSecret;
   bool fGood = vchSecret.SetString(k.get_str());  // Decodes WIF
   CKey key = vchSecret.GetKey();                  // Extracts raw private key
   tempKeystore.AddKey(key);                       // Adds to keystore
   ```

2. **Key Matching Process:**
   - Uses `ProduceSignature()` function
   - `ProduceSignature()` uses the `keystore` to find matching keys
   - **CRITICAL:** It matches keys by trying to sign with each key in the keystore
   - It doesn't derive addresses from WIF - it extracts the raw private key directly

3. **The Matching Logic:**
   - `ProduceSignature()` calls `Solver()` on the scriptPubKey to determine script type
   - For P2PKH (most common), it extracts the pubkey hash from scriptPubKey
   - It then tries each key in the keystore:
     - Derives public key from private key
     - Hashes public key (SHA256 then RIPEMD160)
     - Compares hash to scriptPubKey's pubkey hash
     - If match, uses that key to sign

## 🚨 **The Problem**

The RPC is correctly:
1. ✅ Decoding WIF (using `CTelestaiSecret.SetString()`)
2. ✅ Extracting raw private key
3. ✅ Adding to keystore
4. ✅ Providing prevTxs with scriptPubKey and amount

But it's still failing with "invalid stack size", which means:
- `ProduceSignature()` is trying to sign
- But the public key hash derived from the private key doesn't match the scriptPubKey's pubkey hash

## 💡 **Why This Happens**

The issue is likely in **how the public key is derived from the private key**:

1. **Our app:** Derives compressed public key (33 bytes, starts with 0x02 or 0x03)
2. **RPC expects:** The same compressed public key format
3. **But:** The RPC might be deriving an uncompressed public key, or using a different compression flag

OR:

The scriptPubKey format might be wrong. For P2PKH, scriptPubKey should be:
```
OP_DUP OP_HASH160 <20-byte pubkey hash> OP_EQUALVERIFY OP_CHECKSIG
```

Which in hex is: `76a914<pubkey_hash_hex>88ac`

## 🔧 **The Solution**

### **Option 1: Verify Public Key Compression**

The WIF includes a compression flag (0x01), but we need to ensure:
- The private key is used to derive a **compressed** public key
- The public key hash matches the scriptPubKey's hash

**Check:** Does `CTelestaiSecret.GetKey()` return a key that generates compressed or uncompressed public keys?

### **Option 2: Verify scriptPubKey Format**

The scriptPubKey we're providing might be incorrect. It should be:
- For P2PKH: `76a914<20-byte-hash>88ac`
- The 20-byte hash should be RIPEMD160(SHA256(compressed_public_key))

**Check:** Does our scriptPubKey match what the RPC expects?

### **Option 3: Import Key First (Workaround)**

Even though the code shows keys can be provided in the call, the RPC might work better if:
1. Import the key first (we know this causes address mismatch, but...)
2. Then sign with empty keys array (use wallet keys)
3. The RPC will use the imported key from wallet

**Problem:** This causes address mismatch (we saw this earlier)

### **Option 4: Use signrawtransactionwithkey (If Available)**

Some Bitcoin forks have `signrawtransactionwithkey` which is designed for this exact use case (keys in call, not in wallet).

**Check:** Does Telestai have this RPC method?

## 🎯 **Root Cause Identified**

From the source code analysis:

### **How Key Matching Works:**

1. **WIF Decoding (`CTelestaiSecret.GetKey()`):**
   ```cpp
   ret.Set(vchData.begin(), vchData.begin() + 32, vchData.size() > 32 && vchData[32] == 1);
   ```
   - Extracts 32-byte private key
   - If 33rd byte exists and is `1`, marks key as **compressed**
   - Otherwise, key is **uncompressed**

2. **Key Matching (`Sign1()` → `CreateSig()`):**
   ```cpp
   if (!keystore->GetKey(address, key))
       return false;
   ```
   - `address` is a `CKeyID` (20-byte pubkey hash extracted from scriptPubKey)
   - `keystore->GetKey()` looks up a key by its `CKeyID`
   - It derives the public key from each stored key, hashes it, and compares

3. **The Problem:**
   - When we add a key to `tempKeystore` with `AddKey(key)`, it stores the key
   - The keystore derives the `CKeyID` from the key's **public key**
   - **CRITICAL:** The public key format (compressed vs uncompressed) determines the `CKeyID`
   - If our scriptPubKey has a hash from a **compressed** public key, but the RPC derives an **uncompressed** public key (or vice versa), the `CKeyID` won't match!

### **The Solution:**

**The scriptPubKey we're providing must match the public key format that the RPC derives from our WIF.**

Since we're creating WIF with compression flag `0x01`, the RPC will:
1. Extract the private key
2. Mark it as compressed (because 33rd byte is 1)
3. Derive a **compressed** public key
4. Hash it to get `CKeyID`
5. Try to match this `CKeyID` to the one in scriptPubKey

**Therefore:** Our scriptPubKey must contain the hash of a **compressed** public key.

**The Fix:**
1. Verify that when we derive addresses in our app, we're using **compressed** public keys
2. Verify that the scriptPubKey we're providing has the hash of the **compressed** public key
3. If we're using uncompressed keys anywhere, that's the mismatch!

## 🔧 **The Complete Solution**

### **Step 1: Ensure scriptPubKey is Always Provided**

The code currently sets `scriptPubKey: ""` when constructing UTXOs from the explorer API. We need to:
1. Always fetch scriptPubKey from `getrawtransaction` if it's missing
2. Verify the scriptPubKey format is correct (P2PKH: `76a914<20-byte-hash>88ac`)

### **Step 2: Verify Public Key Compression Match**

The RPC derives public keys from WIF based on the compression flag:
- WIF with 33rd byte = `0x01` → **compressed** public key
- WIF without 33rd byte or `0x00` → **uncompressed** public key

**Our app:**
- ✅ Uses compressed public keys (33 bytes, prefix 0x02/0x03)
- ✅ Creates WIF with compression flag `0x01`
- ✅ Derives addresses from compressed public keys

**The RPC:**
- ✅ Should derive compressed public key from WIF (because 33rd byte is 1)
- ✅ Should hash it to get CKeyID
- ✅ Should match this CKeyID to scriptPubKey's hash

**The Problem:** If the scriptPubKey we provide has a hash from an **uncompressed** public key, but the RPC derives a **compressed** public key, the CKeyID won't match!

### **Step 3: Verify scriptPubKey Hash Matches Our Public Key**

We need to:
1. Derive the public key from our private key (compressed, 33 bytes)
2. Hash it: `RIPEMD160(SHA256(compressed_public_key))`
3. Extract the hash from scriptPubKey: `76a914<20-byte-hash>88ac`
4. Compare the two hashes - they must match!

### **Step 4: The Fix**

**Most Likely Issue:** The scriptPubKey we're providing might have a hash from an **uncompressed** public key, while our WIF tells the RPC to use a **compressed** public key.

**Solution:**
1. When we fetch scriptPubKey from `getrawtransaction`, verify it matches our compressed public key hash
2. If it doesn't match, we might need to:
   - Try deriving an uncompressed public key and see if that hash matches
   - Or verify that the transaction was actually created with a compressed key

**Alternative:** The RPC might be incorrectly handling the compression flag. We could try:
- Creating WIF without compression flag (uncompressed)
- See if that makes the CKeyID match

## 📋 **Implementation Steps**

1. **Add scriptPubKey validation:**
   - When fetching from `getrawtransaction`, verify format
   - Extract pubkey hash and compare to our derived public key hash

2. **Add logging:**
   - Log the scriptPubKey we're sending
   - Log the public key we derive from private key
   - Log both hashes for comparison

3. **Test both compression formats:**
   - Try with compressed WIF (current)
   - Try with uncompressed WIF (if compressed fails)
   - See which one matches the scriptPubKey


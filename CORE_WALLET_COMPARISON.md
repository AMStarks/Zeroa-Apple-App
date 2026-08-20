# Core Wallet & Daemon Requirements Comparison

## 🔍 Current Issue: OP_EQUALVERIFY Script Verification Failure

### Error Details
- **Error:** `16: mandatory-script-verify-flag-failed (Script failed an OP_EQUALVERIFY operation)`
- **What it means:** The script execution is failing at the OP_EQUALVERIFY step in P2PKH script verification
- **Status:** Public key hash matches scriptPubKey hash ✅, but script verification still fails ❌

---

## 📊 Comparison: Our Implementation vs Core Wallet

### 1. **Signature Hash Computation**

#### **Core Wallet (Bitcoin/Telestai Core):**
```cpp
// From Core wallet source (CTransactionSignatureSerializer)
// Serializes transaction for signature hash:
1. Version (4 bytes, little-endian)
2. Input count (varint)
3. For each input:
   - Previous txid (32 bytes, reversed)
   - Previous vout (4 bytes, little-endian)
   - scriptCode length (varint) + scriptCode (the scriptPubKey for P2PKH)
   - Sequence (4 bytes, little-endian)
4. Output count (varint)
5. For each output:
   - Value (8 bytes, little-endian)
   - ScriptPubKey length (varint) + ScriptPubKey
6. Locktime (4 bytes, little-endian)
7. SIGHASH type (4 bytes, little-endian)
8. Double SHA256
```

#### **Our Implementation:**
```swift
// ClientSideTransactionSigner.swift
// ✅ CORRECT - Matches Core wallet exactly:
1. Version (4 bytes, little-endian) ✅
2. Inputs serialized with scriptCode (scriptPubKey) ✅
3. Outputs serialized ✅
4. Locktime (4 bytes, little-endian) ✅
5. SIGHASH type (4 bytes, little-endian) ✅
6. Double SHA256 ✅
```

**Status:** ✅ **MATCHES Core wallet algorithm**

---

### 2. **ScriptSig Format**

#### **Core Wallet:**
```
For P2PKH:
scriptSig = <signature> <public_key>
- Signature: DER-encoded (r, s) + SIGHASH byte
- Public key: 33 bytes compressed (0x02 or 0x03 prefix)
```

#### **Our Implementation:**
```swift
// buildScriptSig() in ClientSideTransactionSigner.swift
scriptSig = <signature_length> <DER_signature + SIGHASH> <pubkey_length> <compressed_public_key>
// ✅ CORRECT format
```

**Status:** ✅ **MATCHES Core wallet format**

---

### 3. **Script Execution (What Daemon Expects)**

#### **P2PKH Script Execution Order:**
```
1. Push signature from scriptSig
2. Push public key from scriptSig
3. OP_DUP (duplicate public key)
4. OP_HASH160 (hash the public key: RIPEMD160(SHA256(pubkey)))
5. Push pubkey hash from scriptPubKey
6. OP_EQUALVERIFY (verify hashes match - FAILS HERE if mismatch)
7. OP_CHECKSIG (verify signature against transaction)
```

#### **What Our Logs Show:**
```
✅ Public key hash matches scriptPubKey hash (verified before signing)
✅ Signature verified locally (isValidSignature passes)
❌ But daemon rejects with OP_EQUALVERIFY error
```

**Status:** ⚠️ **MISMATCH - Something is wrong despite local verification**

---

## 🔬 Potential Issues

### **Issue 1: Signature Hash Computation Error**

**Possibility:** The signature hash we compute might not match what the daemon computes when verifying.

**Why this matters:**
- Core wallet computes signature hash on transaction with **empty scriptSigs**
- Daemon verifies signature by recomputing the hash on the **signed transaction**
- If our hash computation is wrong, the signature won't verify

**Check:**
- Are we using the correct transaction state (empty scriptSigs) when computing hash? ✅ Yes
- Are we serializing inputs/outputs in the correct order? ✅ Yes
- Are we using the correct scriptCode (full scriptPubKey for P2PKH)? ✅ Yes

### **Issue 2: Transaction State Mismatch**

**Possibility:** The transaction we're signing might not match the transaction the daemon receives.

**Why this matters:**
- We parse the raw transaction from `createrawtransaction`
- We sign it and serialize it back
- If serialization is wrong, the daemon sees a different transaction

**Check:**
- Are we correctly parsing the raw transaction? ✅ Yes
- Are we correctly serializing the signed transaction? ⚠️ Need to verify

### **Issue 3: ScriptSig Format Issue**

**Possibility:** The scriptSig format might be slightly wrong, causing script execution to fail.

**Why this matters:**
- Script execution is very strict
- Even a small format error can cause OP_EQUALVERIFY to fail
- The error might be in how we push the signature or public key

**Check:**
- Signature length encoding (OP_PUSHDATA vs direct push)? ✅ Correct
- Public key length encoding? ✅ Correct (33 bytes, direct push)
- DER signature format? ⚠️ Need to verify

### **Issue 4: Signature Verification Context**

**Possibility:** The daemon might be verifying the signature in a different context than we expect.

**Why this matters:**
- Core wallet's `OP_CHECKSIG` verifies: `signature.verify(transaction_hash, public_key)`
- The transaction hash used for verification must match what we signed
- If the transaction we send differs from what we signed, verification fails

**Check:**
- Are we sending the exact transaction we signed? ⚠️ Need to verify
- Does the serialized transaction match what we computed the hash on? ⚠️ Need to verify

---

## 🔍 What Core Wallet Does Differently

### **Core Wallet's SignTransaction Flow:**

1. **Create Transaction:**
   ```cpp
   CTransaction tx;
   // Add inputs (with empty scriptSigs)
   // Add outputs
   ```

2. **Sign Each Input:**
   ```cpp
   for each input:
     // Compute signature hash (using empty scriptSigs)
     uint256 hash = SignatureHash(scriptCode, tx, inputIndex, SIGHASH_ALL);
     
     // Sign with private key
     std::vector<unsigned char> vchSig;
     key.Sign(hash, vchSig);
     
     // Convert to DER + append SIGHASH
     vchSig.push_back(SIGHASH_ALL);
     
     // Build scriptSig
     scriptSig << vchSig << ToByteVector(pubkey);
     
     // Update transaction
     tx.vin[inputIndex].scriptSig = scriptSig;
   ```

3. **Serialize and Broadcast:**
   ```cpp
   CDataStream ss(SER_NETWORK, PROTOCOL_VERSION);
   ss << tx;
   // Send hex to network
   ```

### **Key Differences to Check:**

1. **ScriptCode Format:**
   - Core wallet uses the **full scriptPubKey** as scriptCode for P2PKH ✅ (We do this)
   - For other script types, it might use a different scriptCode

2. **Signature Format:**
   - Core wallet uses DER encoding ✅ (We do this)
   - Appends SIGHASH byte ✅ (We do this)

3. **Transaction Serialization:**
   - Core wallet uses `CDataStream` with specific protocol version
   - We use manual serialization - need to verify it matches

---

## 🎯 What the Daemon Expects

### **Daemon's Transaction Verification:**

1. **Receives signed transaction hex**
2. **Deserializes transaction**
3. **For each input:**
   - Extracts scriptSig (signature + public key)
   - Extracts scriptPubKey from previous transaction output
   - Executes script: `scriptSig + scriptPubKey`
   - Verifies OP_EQUALVERIFY (hash match)
   - Verifies OP_CHECKSIG (signature match)

### **Critical Requirements:**

1. **ScriptSig must be valid:**
   - Signature must be DER-encoded
   - Public key must be 33 bytes compressed
   - Both must be correctly pushed onto stack

2. **Signature must verify:**
   - Signature hash must match what was signed
   - Public key must match the signature
   - Transaction must match what was signed

3. **Public key hash must match:**
   - Hash of public key in scriptSig must equal hash in scriptPubKey
   - This is what OP_EQUALVERIFY checks

---

## 🔧 What We Need to Verify

### **1. Transaction Serialization**
- [ ] Does our serialized transaction match Core wallet format?
- [ ] Are all fields in the correct byte order?
- [ ] Are varints encoded correctly?

### **2. Signature Hash Computation**
- [ ] Does our signature hash match what Core wallet would compute?
- [ ] Are we using the correct scriptCode?
- [ ] Are we serializing inputs/outputs in the correct order?

### **3. ScriptSig Format**
- [ ] Is the DER signature encoding correct?
- [ ] Is the public key format correct?
- [ ] Are the push operations correct?

### **4. Transaction State**
- [ ] Are we signing the correct transaction state?
- [ ] Does the signed transaction match what we computed the hash on?

---

## 💡 Next Steps

1. **Add detailed logging** to compare our computation with Core wallet
2. **Verify transaction serialization** matches Core wallet format
3. **Test with a known-good transaction** to compare formats
4. **Check if there's a byte-order or encoding issue** in our serialization

The fact that public key hash matches but script verification fails suggests the issue is in:
- Signature hash computation (most likely)
- Transaction serialization (possible)
- ScriptSig format (less likely, but possible)

---

## 🔴 **CRITICAL DIFFERENCE: Signature Hash vs Transaction Verification**

### **How Core Wallet/Daemon Verifies:**

1. **Daemon receives signed transaction**
2. **For each input:**
   - Extracts scriptPubKey from previous transaction output
   - **Recomputes signature hash** using:
     - The signed transaction (with scriptSigs)
     - But uses **empty scriptSig** for the input being verified
     - Uses scriptPubKey as scriptCode
   - Verifies signature against recomputed hash

### **What We Do:**

1. **Compute signature hash** on transaction with empty scriptSigs ✅
2. **Sign the hash** ✅
3. **Add scriptSig to transaction** ✅
4. **Serialize and send** ✅

### **Potential Issue:**

The daemon might be recomputing the signature hash differently than we computed it. The key question is:

**Does the daemon use the same transaction state we used when computing the hash?**

- We compute hash on: transaction with **all empty scriptSigs**
- Daemon verifies on: transaction with **scriptSigs filled in, but uses empty scriptSig for the input being verified**

**This should be the same**, but there might be a subtle difference in how we serialize vs how the daemon serializes.

---

## 🎯 **Most Likely Root Cause**

Based on the error and comparison:

**The signature hash we compute doesn't match what the daemon computes when verifying.**

This could be because:
1. **Transaction serialization order** - We might be serializing fields in a different order
2. **Varint encoding** - Our varint encoding might differ slightly
3. **Byte order** - Some field might be in wrong byte order
4. **Transaction version** - We might be using wrong version
5. **Locktime handling** - Locktime might be handled differently

The detailed logging we added will help identify which of these is the issue.


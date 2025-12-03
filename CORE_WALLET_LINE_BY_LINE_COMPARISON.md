# Line-by-Line Comparison: Core Wallet vs Our Implementation

## 🔍 Critical Functions to Compare

### 1. **SignatureHash Computation** (Most Critical)

#### **Bitcoin Core Source (script/interpreter.cpp):**

```cpp
// Bitcoin Core's SignatureHash implementation
uint256 SignatureHash(const CScript& scriptCode, const CTransaction& txTo, 
                      unsigned int nIn, int nHashType, const CAmount& amount, 
                      SigVersion sigversion)
{
    // ... validation ...
    
    // Create a copy of the transaction
    CTransaction txTmp(txTo);
    
    // CRITICAL: Set all scriptSigs to empty
    for (unsigned int i = 0; i < txTmp.vin.size(); i++) {
        txTmp.vin[i].scriptSig = CScript();
    }
    
    // Set the scriptCode for the input being signed
    if (nIn < txTmp.vin.size()) {
        txTmp.vin[nIn].scriptSig = scriptCode;
    }
    
    // Serialize based on SIGHASH flags
    // ... serialization logic ...
    
    // Double SHA256
    CHashWriter ss(SER_GETHASH, 0);
    ss << txTmp << nHashType;
    return ss.GetHash();
}
```

#### **Our Implementation (ClientSideTransactionSigner.swift, lines 415-524):**

```swift
private func computeSignatureHash(
    transaction: ParsedTransaction,
    inputIndex: Int,
    scriptPubKey: Data,
    amount: Double,
    sighashType: UInt8
) throws -> CryptoKit.SHA256.Digest {
    // ✅ CORRECT: Create copy with empty scriptSigs
    var txForHash = transaction
    for i in 0..<txForHash.inputs.count {
        txForHash.inputs[i].scriptSig = Data() // ✅ CORRECT
    }
    
    // ❌ POTENTIAL ISSUE: We're NOT setting scriptCode for the input being signed
    // Core Wallet does: txTmp.vin[nIn].scriptSig = scriptCode;
    // We're using scriptPubKey in serializeInput() instead
    
    // ... serialization ...
    
    // ✅ CORRECT: Double SHA256
    let firstHash = CryptoKit.SHA256.hash(data: buffer)
    let finalHash = CryptoKit.SHA256.hash(data: Data(firstHash))
    return finalHash
}
```

**🔴 CRITICAL DIFFERENCE FOUND:**

**Core Wallet:**
- Sets `txTmp.vin[nIn].scriptSig = scriptCode` (the scriptPubKey) for the input being signed
- Then serializes the transaction with this scriptSig in place

**Our Implementation:**
- Keeps all scriptSigs empty
- Passes `scriptPubKey` separately to `serializeInput()` as `scriptCode`

**This should be equivalent**, but let's verify the serialization matches exactly.

---

### 2. **Input Serialization for SignatureHash**

#### **Bitcoin Core:**

```cpp
// When serializing for SignatureHash:
// For the input being signed (nIn):
//   - prevTxid (32 bytes, reversed)
//   - prevVout (4 bytes, little-endian)
//   - scriptCode length (varint) + scriptCode (the scriptPubKey)
//   - sequence (4 bytes, little-endian)

// For other inputs:
//   - prevTxid
//   - prevVout
//   - empty scriptSig (0x00)
//   - sequence (or 0 if SIGHASH_SINGLE/NONE)
```

#### **Our Implementation (lines 526-553):**

```swift
private func serializeInput(buffer: inout Data, transaction: ParsedTransaction, 
                           inputIndex: Int, scriptPubKey: Data, 
                           hashSingle: Bool, hashNone: Bool, 
                           isSigningInput: Bool = true) {
    let input = transaction.inputs[inputIndex]
    
    // ✅ CORRECT: Previous txid (32 bytes, reversed)
    buffer.append(input.prevTxid)
    
    // ✅ CORRECT: Previous vout (4 bytes, little-endian)
    buffer.append(contentsOf: withUnsafeBytes(of: input.prevVout.littleEndian) { Data($0) })
    
    // ✅ CORRECT: ScriptCode length + scriptCode
    if isSigningInput {
        writeVarInt(buffer: &buffer, value: UInt64(scriptPubKey.count))
        buffer.append(scriptPubKey)
    } else {
        writeVarInt(buffer: &buffer, value: 0) // ✅ CORRECT: Empty script
    }
    
    // ✅ CORRECT: Sequence handling
    let sequence: UInt32
    if !isSigningInput && (hashSingle || hashNone) {
        sequence = 0
    } else {
        sequence = input.sequence
    }
    buffer.append(contentsOf: withUnsafeBytes(of: sequence.littleEndian) { Data($0) })
}
```

**✅ This matches Core Wallet's logic**

---

### 3. **Output Serialization**

#### **Bitcoin Core:**

```cpp
// For each output (depending on SIGHASH flags):
//   - value (8 bytes, little-endian)
//   - scriptPubKey length (varint)
//   - scriptPubKey
```

#### **Our Implementation (lines 555-564):**

```swift
private func serializeOutput(buffer: inout Data, output: TransactionOutput) {
    // ✅ CORRECT: Value (8 bytes, little-endian)
    buffer.append(contentsOf: withUnsafeBytes(of: output.value.littleEndian) { Data($0) })
    
    // ✅ CORRECT: ScriptPubKey length (varint)
    writeVarInt(buffer: &buffer, value: UInt64(output.scriptPubKey.count))
    
    // ✅ CORRECT: ScriptPubKey
    buffer.append(output.scriptPubKey)
}
```

**✅ This matches Core Wallet**

---

### 4. **SIGHASH Type Serialization**

#### **Bitcoin Core:**

```cpp
// SIGHASH type is serialized as 4 bytes (UInt32), little-endian
CHashWriter ss(SER_GETHASH, 0);
ss << txTmp << nHashType;  // nHashType is int, serialized as 4 bytes
```

#### **Our Implementation (lines 503-505):**

```swift
// SIGHASH type (4 bytes, little-endian) - Bitcoin uses 4 bytes for this
let sighashTypeUInt32 = UInt32(sighashType)
buffer.append(contentsOf: withUnsafeBytes(of: sighashTypeUInt32.littleEndian) { Data($0) })
```

**✅ This matches Core Wallet**

---

### 5. **ScriptSig Building**

#### **Bitcoin Core:**

```cpp
// In SignTransaction():
// For P2PKH:
//   scriptSig = <signature> <public_key>
//   - Signature: DER-encoded (r, s) + SIGHASH byte
//   - Public key: 33 bytes compressed

// Serialization:
//   - Push signature length (varint) + signature
//   - Push public key length (varint) + public key
```

#### **Our Implementation (lines 585-608):**

```swift
private func buildScriptSig(signature: Data, publicKey: Data) -> Data {
    var scriptSig = Data()
    
    // ✅ CORRECT: Push signature
    if signature.count <= 75 {
        scriptSig.append(UInt8(signature.count)) // Direct push
    } else if signature.count <= 255 {
        scriptSig.append(0x4c) // OP_PUSHDATA1
        scriptSig.append(UInt8(signature.count))
    } else {
        scriptSig.append(0x4d) // OP_PUSHDATA2
        scriptSig.append(contentsOf: withUnsafeBytes(of: UInt16(signature.count).littleEndian) { Data($0) })
    }
    scriptSig.append(signature)
    
    // ✅ CORRECT: Push public key (33 bytes, direct push)
    scriptSig.append(UInt8(publicKey.count)) // Always 33
    scriptSig.append(publicKey)
    
    return scriptSig
}
```

**✅ This matches Core Wallet**

---

### 6. **DER Signature Encoding**

#### **Bitcoin Core:**

```cpp
// In key.cpp or script/sign.cpp:
// Signature is DER-encoded:
//   0x30 [length] 0x02 [r_length] [r] 0x02 [s_length] [s]
// With low-s normalization
```

#### **Our Implementation (lines 662-713):**

```swift
private func encodeDERSignature(r: Data, s: Data) throws -> Data {
    // ✅ CORRECT: Remove leading zeros
    var rTrimmed = r
    while rTrimmed.count > 1 && rTrimmed.first == 0 {
        rTrimmed = rTrimmed.dropFirst()
    }
    
    // ✅ CORRECT: Ensure first byte < 0x80 (not negative)
    if rTrimmed.first! >= 0x80 {
        rTrimmed = Data([0x00]) + rTrimmed
    }
    
    // Same for s...
    
    // ✅ CORRECT: Build DER structure
    var der = Data()
    der.append(0x30) // SEQUENCE
    // ... length encoding ...
    der.append(0x02) // INTEGER
    der.append(UInt8(rLen))
    der.append(rTrimmed)
    der.append(0x02) // INTEGER
    der.append(UInt8(sLen))
    der.append(sTrimmed)
    
    return der
}
```

**✅ This matches Core Wallet**

---

## 🔴 **POTENTIAL ISSUES FOUND**

### **Issue 1: Transaction State for Hash Computation**

**Core Wallet:**
```cpp
// Sets scriptSig for the input being signed to scriptCode
txTmp.vin[nIn].scriptSig = scriptCode;
// Then serializes the entire transaction
```

**Our Implementation:**
```swift
// Keeps all scriptSigs empty
// Passes scriptPubKey separately to serializeInput()
```

**Analysis:** This should be equivalent, but we need to verify that when Core Wallet serializes `txTmp.vin[nIn].scriptSig = scriptCode`, it produces the same bytes as our `serializeInput()` with `scriptPubKey` parameter.

**Verification:** The serialization should match because:
- Core Wallet: serializes `scriptCode` as part of `txTmp.vin[nIn].scriptSig`
- Our code: serializes `scriptPubKey` directly in `serializeInput()`

Both should produce: `[varint length][scriptPubKey bytes]`

---

### **Issue 2: Transaction Version Serialization**

**Core Wallet:**
```cpp
// Uses CHashWriter which handles version as 4 bytes little-endian
ss << txTmp;  // Serializes version as 4 bytes
```

**Our Implementation:**
```swift
// Version (4 bytes, little-endian)
buffer.append(contentsOf: withUnsafeBytes(of: txForHash.version.littleEndian) { Data($0) })
```

**✅ This should match**

---

### **Issue 3: Locktime Serialization**

**Core Wallet:**
```cpp
// Locktime serialized as 4 bytes little-endian
ss << txTmp;  // Includes locktime
```

**Our Implementation:**
```swift
// Locktime (4 bytes, little-endian)
buffer.append(contentsOf: withUnsafeBytes(of: txForHash.locktime.littleEndian) { Data($0) })
```

**✅ This should match**

---

## 🎯 **What to Check Next**

1. **Verify the exact byte sequence** produced by our `computeSignatureHash()` matches what Core Wallet would produce
2. **Check if there's a difference** in how we handle the transaction copy vs Core Wallet
3. **Verify the signed transaction** (with scriptSigs) matches what we computed the hash on (minus scriptSig)

The verification code we added should reveal if there's a mismatch!



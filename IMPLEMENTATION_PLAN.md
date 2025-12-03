# Implementation Plan: Fix Transaction Signing

## Root Cause Identified

From examining the Core Wallet source code:

1. **Keystore indexing works correctly:**
   - `AddKey(key)` → `AddKeyPubKey(key, key.GetPubKey())`
   - `AddKeyPubKey` does: `mapKeys[pubkey.GetID()] = key;`
   - `pubkey.GetID()` does: `CKeyID(Hash160(vch, vch + size()))`
   - This creates a mapping: `CKeyID (pubkey hash) → CKey (private key)`

2. **Signing process:**
   - `ProduceSignature` calls `Solver(scriptPubKey, whichTypeRet, vSolutions)`
   - For P2PKH, `vSolutions[0]` contains the 20-byte pubkey hash
   - `keyID = CKeyID(uint160(vSolutions[0]))`
   - `Sign1(keyID, creator, scriptPubKey, ret, sigversion)` calls `CreateSig`
   - `CreateSig` calls `keystore->GetKey(address, key)` where `address` is the CKeyID
   - `GetKey` looks up: `mapKeys.find(address)`

3. **The Problem:**
   - We've verified the scriptPubKey hash matches our derived public key hash ✅
   - The keystore should have the key indexed by that CKeyID ✅
   - But `GetKey` is still failing ❌

## Most Likely Issue

The issue is that **the RPC might be deriving a different public key format** than what we expect, OR there's a **parameter encoding issue** where the prevTxs aren't being processed correctly.

## Solution: Implement Client-Side Signing

Since we have:
- ✅ All crypto primitives (secp256k1)
- ✅ Transaction construction logic
- ✅ ScriptPubKey format understanding
- ✅ Signature creation capability

**We should implement full client-side signing** which:
1. Bypasses RPC signing entirely
2. Signs the transaction in the app
3. Sends the signed transaction to RPC for broadcast only
4. More secure (keys never leave device)
5. Doesn't depend on RPC keystore behavior

## Implementation Steps

1. **Create `ClientSideSigner` class:**
   - Sign raw transaction inputs
   - Handle SIGHASH flags
   - Create proper scriptSig

2. **Update `TLSBlockchainService.sendPayment`:**
   - Use client-side signing instead of RPC signing
   - Only use RPC for `createrawtransaction` and `sendrawtransaction`

3. **Test and verify:**
   - Ensure signatures are valid
   - Ensure transactions broadcast successfully


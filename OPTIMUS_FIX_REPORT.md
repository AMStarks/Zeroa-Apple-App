# Optimus Server Fix Report

## 1. Firewall Configuration ✅

**Status:** Configured and active

**Actions Taken:**
- ✅ Verified UFW firewall is active
- ✅ Ports 22 and 2222 are open for SSH
- ✅ SSH service is running and listening on 0.0.0.0:22 (all interfaces)
- ✅ fail2ban is not blocking connections

**External Access Note:**
- Local network access (192.168.0.121:22) works ✅
- External access (114.73.209.140:22) times out ❌
- **This requires router port forwarding configuration** (port 22 → 192.168.0.121:22)
- Router gateway: 192.168.0.1

**SSH Configuration:**
- Port: 22 (default)
- PubkeyAuthentication: yes
- PasswordAuthentication: yes
- PermitRootLogin: no

## 2. Daemon Implementation Review ✅

**Examined Files:**
- `/tmp/telestai/src/rpc/rawtransaction.cpp` - signrawtransaction implementation
- `/tmp/telestai/src/keystore.cpp` - keystore AddKey/GetKey logic
- `/tmp/telestai/src/script/sign.cpp` - ProduceSignature and CreateSig logic

**Key Findings:**

1. **Keystore Indexing (CORRECT):**
   ```cpp
   bool CBasicKeyStore::AddKeyPubKey(const CKey& key, const CPubKey &pubkey) {
       mapKeys[pubkey.GetID()] = key;  // Indexes by CKeyID (pubkey hash)
   }
   ```

2. **Signing Flow:**
   - RPC creates `tempKeystore` and adds keys via `AddKey(key)`
   - `ProduceSignature` extracts CKeyID from scriptPubKey
   - `CreateSig` calls `keystore->GetKey(CKeyID, key)`
   - If `GetKey` fails → no signature created → verification fails → "invalid stack size" error

3. **The Problem:**
   - We've verified scriptPubKey hash matches our derived public key hash ✅
   - Keystore should have key indexed by that CKeyID ✅
   - But `GetKey` is still failing ❌

**Possible Causes:**
1. Parameter encoding issue (prevTxs not processed correctly)
2. Public key format mismatch (compressed vs uncompressed)
3. CKeyID extraction from scriptPubKey doesn't match keystore index

## 3. Recommended Solution

**Implement Full Client-Side Signing** (Most Reliable)

**Why:**
- ✅ Bypasses RPC keystore entirely
- ✅ More secure (keys never leave device)
- ✅ Doesn't depend on RPC behavior
- ✅ We have all crypto primitives needed

**Implementation:**
1. Sign raw transaction inputs directly in the app
2. Create proper scriptSig with signatures
3. Only use RPC for `createrawtransaction` and `sendrawtransaction`

**Alternative (If we want to keep RPC signing):**
- Debug parameter encoding
- Verify prevTxs format matches RPC expectations
- Test with direct RPC calls to isolate issue

## 4. Next Steps

### Immediate:
1. **Router Configuration** (User Action Required):
   - Configure port forwarding: External 22 → Internal 192.168.0.121:22
   - Or use port 2222 if already configured

2. **Implement Client-Side Signing:**
   - Create `ClientSideSigner` class
   - Update `TLSBlockchainService.sendPayment`
   - Test with real transactions

### Testing:
1. Test external SSH access after router config
2. Test transaction signing with client-side implementation
3. Verify transactions broadcast successfully

## 5. Current Status

- ✅ Server accessible locally
- ✅ Firewall configured
- ✅ Daemon code reviewed
- ⏳ External access needs router config
- ⏳ Client-side signing implementation pending


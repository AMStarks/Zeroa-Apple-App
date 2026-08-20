# Root Cause Analysis: "Unable to sign input, invalid stack size"

## What We Know Works ✅

1. **scriptPubKey hash matches our derived public key hash**
   - scriptPubKey hash: `635afe075b544adec23f6b96246505292bd53865`
   - Derived hash (compressed): `635afe075b544adec23f6b96246505292bd53865`
   - **Match: ✅ YES**

2. **WIF format is correct**
   - Compressed WIF (0x80) generated successfully
   - Address verification passed
   - WIF length: 52 characters (correct for compressed)

3. **prevTxs provided correctly**
   - scriptPubKey, amount, txid, vout all present
   - Format: P2PKH (`76a914...88ac`)

## What's Failing ❌

The RPC returns:
- `"scriptSig": ""` (empty - no signature created)
- `"complete": false`
- Error: "Unable to sign input, invalid stack size (possibly missing key)"

## The Critical Question

**Why can't the RPC match the key to the scriptPubKey when:**
- The public key hash matches ✅
- The WIF is valid ✅
- The prevTxs are provided ✅

## What We're Missing

We need to verify:

1. **Is the RPC actually receiving the parameters correctly?**
   - Are prevTxs being encoded properly?
   - Are privateKeys being sent as an array?
   - Is the parameter order correct?

2. **Is the RPC's keystore properly indexing keys?**
   - When `AddKey(key)` is called, does it create the CKeyID mapping?
   - Is the keystore lookup working?

3. **Is there a bug in the RPC implementation?**
   - Does the temporary keystore work correctly?
   - Does it check wallet keys before tempKeystore?

## Next Steps to Diagnose

1. **Add detailed logging** to see exact JSON being sent ✅ (just added)
2. **Test RPC directly** with curl to see if it works manually
3. **Check server logs** to see what the RPC daemon is doing
4. **Try importing key first** then signing with empty keys array (workaround)

## Most Likely Root Cause

The RPC's `keystore->GetKey(CKeyID, key)` lookup is failing because:
- Keys are added to `tempKeystore` via `AddKey(key)`
- But the keystore might not be properly indexing them by CKeyID
- OR the RPC checks wallet keys first and skips tempKeystore if address isn't in wallet

## Solution Options

1. **Import key first** (workaround - we know address mismatch happens, but might work for signing)
2. **Client-side signing** (bypass RPC signing entirely - most secure)
3. **Fix RPC keystore** (if it's a bug in the daemon)


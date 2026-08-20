# Next Steps - Zeroa Transaction & Halo API

## Current Status Summary

### ✅ Completed
1. **Transaction Encoding Fixed**
   - Fixed `AnyCodable` encoding for nested dictionaries and arrays
   - Added validation for finite numbers
   - Build successful

2. **RPC Endpoint Fixed**
   - Updated route mounting: `/api/tls` → `/api/tls/rpc`
   - Deployed `tls.js` route file to server
   - Fixed Authorization header handling
   - Added RPC credentials to `.env`
   - Endpoint working: `https://halo.telestai.io/api/tls/rpc`

3. **UTXO Retrieval Improved**
   - Added fallback chain: `getaddressutxos` → `listunspent` → construct from transactions
   - Better error messages
   - Address import scripts created

4. **Address Import**
   - Created `import_address_to_wallet.sh` script
   - Created `import_address_remote.sh` convenience script
   - Address imported: `TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x`
   - Rescan initiated (in progress)

### ⏳ In Progress
1. **Address Rescan**
   - Status: Rescanning blockchain for historical transactions
   - May take 5-15 minutes depending on blockchain size
   - Check with: `./import_address_remote.sh TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x "" false`

### ❌ Missing
1. **Authentication Endpoints**
   - `/api/halo/challenge` - Missing (returns 404)
   - `/api/halo/verify` - Missing (returns 404)
   - Needed for Zeroa/LASKO authentication

---

## Immediate Next Steps

### 1. Wait for Rescan to Complete ⏰
**Priority: High**

The address rescan is currently running. Once complete, UTXOs should be available.

**Check status:**
```bash
# Check if address is now tracked
./import_address_remote.sh TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x "" false

# Or manually check
ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 \
  'curl -s -X POST http://rpc:rpc@127.0.0.1:8766 \
    -H "Content-Type: application/json" \
    -d "{\"method\":\"getaddressutxos\",\"params\":[{\"addresses\":[\"TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x\"]}],\"id\":1}"'
```

**Once UTXOs are available:**
- Test transaction sending in Zeroa app
- Should work without errors now

---

### 2. Implement Missing Authentication Endpoints 🔐
**Priority: High** (if authentication is needed)

The `/api/halo/challenge` and `/api/halo/verify` endpoints are missing but required for:
- Zeroa authentication flow
- LASKO authentication flow
- Token generation

**What needs to be done:**
1. Create `halo-indexer-app/src/routes/auth.js` or `halo.js`
2. Implement challenge endpoint (generate nonce)
3. Implement verify endpoint (verify signature, issue JWT)
4. Mount routes in `index.js`

**Files to create/modify:**
- `halo-indexer-app/src/routes/halo.js` (new)
- `halo-indexer-app/src/index.js` (add route mounting)

---

### 3. Test Transaction Sending 💸
**Priority: High** (after rescan completes)

Once UTXOs are available:
1. Rebuild Zeroa app in Xcode
2. Test sending a transaction
3. Verify:
   - UTXOs are found
   - Transaction is created successfully
   - Transaction is signed
   - Transaction is broadcast

**Expected flow:**
- App calls `listUnspent()` → should return UTXOs
- App creates transaction with UTXOs
- App signs transaction
- App broadcasts via RPC

---

### 4. Test Authentication Flow 🔑
**Priority: Medium** (after endpoints are implemented)

If authentication is needed:
1. Implement challenge/verify endpoints
2. Test Zeroa authentication:
   - Request challenge
   - Sign message
   - Verify signature
   - Receive token
3. Test LASKO authentication:
   - Request token from Zeroa
   - Use token to fetch posts

---

## Testing Checklist

### Transaction Sending
- [ ] Address rescan completed
- [ ] UTXOs available via RPC
- [ ] `listUnspent()` returns UTXOs
- [ ] Transaction creation succeeds
- [ ] Transaction signing succeeds
- [ ] Transaction broadcast succeeds
- [ ] Transaction appears in explorer

### Authentication (if needed)
- [ ] `/api/halo/challenge` endpoint implemented
- [ ] `/api/halo/verify` endpoint implemented
- [ ] Challenge request works
- [ ] Signature verification works
- [ ] JWT token issued
- [ ] Token stored in App Groups
- [ ] LASKO can use token

---

## Quick Commands Reference

### Check Address Status
```bash
./import_address_remote.sh TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x "" false
```

### Check UTXOs
```bash
ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 \
  'curl -s -X POST http://rpc:rpc@127.0.0.1:8766 \
    -H "Content-Type: application/json" \
    -d "{\"method\":\"getaddressutxos\",\"params\":[{\"addresses\":[\"TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x\"]}],\"id\":1}"'
```

### Test RPC Endpoint
```bash
./test_tls_rpc_endpoint.sh http://192.168.0.121/api/tls
```

### Rebuild App
```bash
cd /Users/starkers/Projects/Zeroa
xcodebuild -workspace Zeroa.xcworkspace -scheme Zeroa -configuration Debug -sdk iphonesimulator build
```

---

## Recommended Order

1. **Wait for rescan** (5-15 min) → Check status periodically
2. **Test transaction** → Once UTXOs available, test sending
3. **Implement auth endpoints** → If authentication fails, implement endpoints
4. **Full integration test** → Test complete flow end-to-end

---

## Notes

- **Rescan timing**: Can take 5-15 minutes for 680k+ blocks
- **Fallback code**: App will try to construct UTXOs from transactions if RPC fails
- **Authentication**: May not be critical if you're testing transactions only
- **Server logs**: Check PM2 logs if issues: `ssh ... 'pm2 logs halo-indexer --lines 50'`


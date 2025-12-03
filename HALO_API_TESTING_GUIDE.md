# Halo API Testing Guide - Optimus Server

## Current Status: ✅ API is Working

**Server:** Optimus (192.168.0.121)  
**API Base URL:** `http://192.168.0.121/api`  
**Status:** All critical endpoints responding correctly

---

## Best Route to Test Halo API

### Option 1: Automated Script (Recommended) ⭐

Run the comprehensive test script:

```bash
./test_halo_api_optimus.sh
```

Or test from external IP:
```bash
./test_halo_api_optimus.sh http://114.73.209.140/api
```

**What it tests:**
- ✅ Health endpoint
- ✅ Challenge endpoint (Zeroa)
- ✅ Challenge endpoint (LASKO)
- ✅ Posts endpoint (LASKO)
- ✅ Legacy endpoint fallback

### Option 2: Manual cURL Tests

#### 1. Health Check
```bash
curl http://192.168.0.121/api/health
```

#### 2. Challenge Request (Zeroa)
```bash
curl "http://192.168.0.121/api/halo/challenge?address=ThGNWv22Mb89YwMKo8hAgTEL5ChWcnNuRJ&bundleId=com.telestai.Zeroa"
```

#### 3. Challenge Request (LASKO)
```bash
curl "http://192.168.0.121/api/halo/challenge?address=ThGNWv22Mb89YwMKo8hAgTEL5ChWcnNuRJ&bundleId=com.telestai.LASKO"
```

#### 4. Posts Endpoint (requires auth token)
```bash
curl "http://192.168.0.121/api/posts?limit=5"
```

### Option 3: iOS App Testing (End-to-End)

1. **Rebuild Zeroa app** in Xcode
2. **Test authentication flow:**
   - Login with address and mnemonic
   - Verify challenge request works
   - Verify token is received and stored
   - Check App Groups for token

3. **Rebuild LASKO app** in Xcode
4. **Test LASKO integration:**
   - Request Zeroa authentication
   - Verify posts can be fetched
   - Test posting functionality

---

## API Endpoints Used by Apps

### Zeroa App (`HaloAPIService.swift`)

**Base URL:** `http://192.168.0.121/api`

1. **Challenge Request**
   - Endpoint: `GET /api/halo/challenge`
   - Fallback: `GET /api/auth/challenge` (if 404)
   - Query params: `address`, `bundleId`
   - Used for: Authentication flow

2. **Verify Signature**
   - Endpoint: `POST /api/halo/verify`
   - Fallback: `POST /api/auth/verify` (if 404)
   - Body: `{address, bundleId, nonce, signature, pubkey}`
   - Returns: JWT token

### LASKO App (`LASKOService.swift`)

**Base URL:** `http://192.168.0.121/api`

1. **Fetch Posts**
   - Endpoint: `GET /api/posts`
   - Query params: `limit`, `page`
   - Requires: JWT token in Authorization header

2. **Create Post**
   - Endpoint: `POST /api/posts`
   - Requires: JWT token + signature

3. **Fetch Thread/Comments**
   - Endpoint: `GET /api/posts/{code}/thread`
   - Requires: JWT token

---

## Current Test Results

### ✅ Working Endpoints

| Endpoint | Status | Notes |
|----------|--------|-------|
| `/api/health` | ✅ 200 | Health check working |
| `/api/halo/challenge` | ✅ 200 | Returns nonce correctly |
| `/api/posts` | ✅ 200 | Accessible (returns empty array without auth) |
| `/api/auth/challenge` | ⚠️ 404 | Legacy endpoint (apps have fallback) |

### Server Status

- **PM2 Process:** ✅ Online (halo-indexer)
- **Nginx:** ✅ Running (proxying to port 3000)
- **Redis:** ✅ Healthy
- **Database:** ✅ Healthy
- **Port:** 3000 (listening)

---

## Testing Checklist

### Pre-Flight Checks
- [x] Server accessible via SSH
- [x] PM2 process running
- [x] Nginx configured and running
- [x] Health endpoint responding
- [x] Challenge endpoint working

### Zeroa App Testing
- [ ] App can connect to API
- [ ] Challenge request succeeds
- [ ] Signature verification works
- [ ] Token stored in App Groups
- [ ] Auto-login with token works

### LASKO App Testing
- [ ] Can request Zeroa authentication
- [ ] Can fetch posts with token
- [ ] Can create posts
- [ ] Can fetch thread/comments
- [ ] Error handling works

### Integration Testing
- [ ] Zeroa → LASKO auth flow works
- [ ] Token sharing via App Groups works
- [ ] Both apps can use same token
- [ ] Token refresh works

---

## Troubleshooting

### If API is not responding:

1. **Check PM2 status:**
   ```bash
   ssh -i ~/.ssh/id_optimus -p 2222 chief@114.73.209.140 "pm2 list"
   ```

2. **Check Nginx status:**
   ```bash
   ssh -i ~/.ssh/id_optimus -p 2222 chief@114.73.209.140 "sudo systemctl status nginx"
   ```

3. **Check API directly (bypass nginx):**
   ```bash
   ssh -i ~/.ssh/id_optimus -p 2222 chief@114.73.209.140 "curl http://localhost:3000/api/health"
   ```

4. **Check Nginx logs:**
   ```bash
   ssh -i ~/.ssh/id_optimus -p 2222 chief@114.73.209.140 "sudo tail -f /var/log/nginx/error.log"
   ```

5. **Check PM2 logs:**
   ```bash
   ssh -i ~/.ssh/id_optimus -p 2222 chief@114.73.209.140 "pm2 logs halo-indexer"
   ```

### Common Issues

**Issue:** 404 on `/api/health`
- **Fix:** Check nginx config is proxying to correct port (3000)

**Issue:** Connection refused
- **Fix:** Check PM2 process is running: `pm2 restart halo-indexer`

**Issue:** Apps can't connect
- **Fix:** Verify ATS exceptions in Info.plist for HTTP local IP
- **Fix:** Check firewall allows port 80

---

## Next Steps

1. **Immediate:** Test from iOS apps (rebuild and run)
2. **Verify:** End-to-end authentication flow
3. **Test:** Posting functionality in LASKO
4. **Monitor:** Check logs during app testing
5. **Future:** Switch to HTTPS after SSL certificate setup

---

## Quick Reference

**Test Script:**
```bash
./test_halo_api_optimus.sh
```

**Server Access:**
```bash
ssh -i ~/.ssh/id_optimus -p 2222 chief@114.73.209.140
```

**API Base URL (Current):**
- Local: `http://192.168.0.121/api`
- External: `http://114.73.209.140/api` (if port forwarding configured)

**API Base URL (Future - after SSL):**
- `https://halo.telestai.io/api`


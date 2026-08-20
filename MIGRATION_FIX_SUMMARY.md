# Migration Fix - Global Access Issue

## Problem Identified ✅

**Issue:** Apps were hardcoded to local IP `192.168.0.121` during migration testing
- ❌ Only works on local network
- ❌ Users worldwide can't access
- ❌ This was a temporary testing configuration

## Fix Applied ✅

### 1. Updated Apps to Use External Domain

**Zeroa (`HaloAPIService.swift`):**
- ✅ Changed from: `http://192.168.0.121/api`
- ✅ Changed to: `http://halo.telestai.io/api`
- ✅ Removed cellular restriction (`allowsCellularAccess = true`)
- ✅ Kept improved URLSession configuration (30s timeout, waitsForConnectivity)

**LASKO (`LASKOService.swift`):**
- ✅ Changed from: `http://192.168.0.121/api`
- ✅ Changed to: `http://halo.telestai.io/api`

### 2. DNS Verification ✅

**DNS is correct:**
- `halo.telestai.io` → `114.73.209.140` ✅

## Remaining Issue: Port Forwarding

**Status:** External access not working yet
- DNS points to correct IP ✅
- But server not accessible externally ❌

**Required:** Port forwarding on router
- Port 80 (HTTP) → `192.168.0.121:80`
- Port 443 (HTTPS) → `192.168.0.121:443`

**See:** `PORT_FORWARDING_SETUP.md` for detailed instructions

## Next Steps

### Option 1: Set Up Port Forwarding (Recommended)

1. **Configure router port forwarding:**
   - External Port 80 → Internal `192.168.0.121:80`
   - External Port 443 → Internal `192.168.0.121:443`

2. **Verify external access:**
   ```bash
   curl http://114.73.209.140/api/health
   curl http://halo.telestai.io/api/health
   ```

3. **Set up SSL certificate:**
   ```bash
   ssh -i ~/.ssh/id_optimus -p 2222 chief@114.73.209.140
   sudo certbot --nginx -d halo.telestai.io
   ```

4. **Update apps to HTTPS:**
   - Change `http://halo.telestai.io/api` → `https://halo.telestai.io/api`
   - Remove ATS exceptions from Info.plist

### Option 2: Temporary Workaround (If Port Forwarding Blocked)

If ISP blocks ports 80/443, you can:
1. Use Cloudflare Tunnel (free, no port forwarding needed)
2. Or use non-standard ports (requires Cloudflare config)

## Current Status

**Apps Updated:** ✅
- Zeroa: Using `http://halo.telestai.io/api`
- LASKO: Using `http://halo.telestai.io/api`

**DNS:** ✅ Working (`halo.telestai.io` → `114.73.209.140`)

**External Access:** ⏳ Waiting for port forwarding

**SSL:** ⏳ Waiting for port forwarding (Let's Encrypt needs port 80)

## Testing

**After port forwarding is set up:**

1. **Test from external network:**
   ```bash
   curl http://halo.telestai.io/api/health
   # Should return: {"ok":true} or similar
   ```

2. **Rebuild iOS apps:**
   - Apps now use external domain
   - Should work from anywhere in the world
   - No local network restriction

3. **Test from iPhone:**
   - Can be on any network (WiFi or cellular)
   - Should connect to `halo.telestai.io`
   - No need to be on same network as server

## Summary

✅ **Fixed:** Apps now use external domain instead of local IP
✅ **Fixed:** Removed cellular restriction
⏳ **Pending:** Port forwarding configuration on router
⏳ **Pending:** SSL certificate setup (after port forwarding)

**Once port forwarding is configured, apps will work globally!**


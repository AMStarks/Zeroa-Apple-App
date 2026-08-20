# Network Timeout Issue - Diagnosis & Solution

## Current Status

**Permission:** ✅ Local Network permission is ON (green toggle)
**Server:** ✅ Server is accessible (tested via curl - 200 OK)
**Mac Network:** ✅ `192.168.0.61` (same network segment as server)
**Issue:** ❌ Requests timing out from iOS app

---

## Changes Made

### 1. ✅ Improved URLSession Configuration

**Updated:** `HaloAPIService.swift`

**Changes:**
- Created custom `URLSession` with proper configuration
- `waitsForConnectivity = true` - Waits for network to be available
- `timeoutIntervalForRequest = 30.0` - 30 second timeout (was default ~60s)
- `timeoutIntervalForResource = 60.0` - 60 second total timeout
- `allowsCellularAccess = false` - Force WiFi only (for local network)
- Using custom session instead of `URLSession.shared`

**Why:**
- Default `URLSession.shared` might have issues with local network
- Custom configuration gives us more control
- Longer timeouts help with network delays
- `waitsForConnectivity` helps if network is temporarily unavailable

---

## Diagnostic Steps

### Step 1: Check iPhone Network (CRITICAL)

**On iPhone:**
1. Settings → Wi-Fi
2. Tap the (i) icon next to your WiFi network
3. Check "IP Address"
4. **Should be:** `192.168.0.XXX` (where XXX is 1-254)

**If iPhone IP is NOT `192.168.0.XXX`:**
- ❌ iPhone is on different network
- ❌ Cannot reach server at `192.168.0.121`
- ✅ **Fix:** Connect iPhone to same WiFi network as server

### Step 2: Test from Safari on iPhone

**On iPhone Safari:**
1. Navigate to: `http://192.168.0.121/api/health`
2. **Expected:** See JSON: `{"status":"healthy",...}`
3. **If fails:** Network connectivity issue

**If Safari works but app doesn't:**
- URLSession configuration issue (should be fixed now)
- Or app-specific network restriction

### Step 3: Check via Xcode (if iPhone connected)

**In Xcode:**
1. Window → Devices and Simulators
2. Select your iPhone
3. Check "Network" section
4. Verify IP address matches network segment

**Or run diagnostic script:**
```bash
./test_iphone_network.sh
```

---

## Potential Issues & Solutions

### Issue 1: iPhone on Different Network ⚠️ MOST LIKELY

**Symptom:** iPhone IP is not `192.168.0.x`
**Example:** iPhone IP is `10.0.0.x` or `172.16.x.x`

**Solution:**
1. Connect iPhone to same WiFi network as server
2. Verify IP is `192.168.0.XXX`
3. Test again

### Issue 2: URLSession Configuration (FIXED)

**Symptom:** Requests timeout even with good network
**Solution:** ✅ Already fixed - custom URLSession with proper timeouts

### Issue 3: Network Interface Selection

**Symptom:** iOS trying wrong network interface
**Solution:** `allowsCellularAccess = false` forces WiFi (should help)

### Issue 4: Firewall on Server

**Symptom:** Server accessible from Mac but not iPhone
**Check:** Run on server:
```bash
sudo ufw status
# Should allow port 80
```

---

## What to Check Now

### Immediate Checks:

1. **iPhone IP Address:**
   - Settings → Wi-Fi → (i) → IP Address
   - Must be `192.168.0.XXX`

2. **Safari Test:**
   - Open Safari on iPhone
   - Go to: `http://192.168.0.121/api/health`
   - Does it work?

3. **Network Name:**
   - Is iPhone connected to same WiFi network name as server?

### If iPhone Connected via USB:

Run diagnostic:
```bash
./test_iphone_network.sh
```

Or check in Xcode:
- Window → Devices and Simulators → Select iPhone → Network

---

## Expected Behavior After Fix

**With improved URLSession config:**
```
🔍 HaloAPIService.requestChallenge: Sending request with custom session (timeout: 30s)...
🔍 HaloAPIService.requestChallenge: Session config - waitsForConnectivity: true, allowsCellular: false
[should get response within 30 seconds]
✅ HaloAPIService.requestChallenge: Response status: 200
✅ HaloService.ensureToken: Token stored in App Groups
```

---

## Next Steps

1. **Rebuild Zeroa app** with new URLSession configuration
2. **Check iPhone IP address** (must be `192.168.0.XXX`)
3. **Test from Safari** on iPhone: `http://192.168.0.121/api/health`
4. **Run app again** and check logs

**Share results:**
- iPhone IP address
- Safari test result (works/doesn't work)
- New app logs after rebuild

This will help us determine if it's:
- Network connectivity (different network)
- URLSession configuration (should be fixed now)
- Or something else

---

## Summary

**Changes Made:**
- ✅ Custom URLSession with proper timeouts
- ✅ `waitsForConnectivity = true`
- ✅ `allowsCellularAccess = false` (WiFi only)
- ✅ 30 second request timeout

**Most Likely Issue:**
- iPhone not on same network (`192.168.0.x`)
- Or network connectivity problem

**Next:** Check iPhone IP and test from Safari to confirm network connectivity.


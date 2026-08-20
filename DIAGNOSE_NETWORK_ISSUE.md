# Network Issue Diagnosis - iPhone Connected

## Issue Summary

**Problem:** Requests to `http://192.168.0.121/api/halo/challenge` are timing out
**Permission:** ✅ Local Network permission is granted (toggle is ON)
**Server:** ✅ Server is accessible (tested via curl - 200 OK in 0.06s)
**Your Mac IP:** `192.168.0.61` (same network segment)

---

## Diagnostic Steps

### Step 1: Check iPhone Network Configuration

**On iPhone (when connected):**

1. **Check iPhone IP Address:**
   - Settings → Wi-Fi → Tap the (i) next to your network
   - Look for "IP Address" - should be `192.168.0.x`
   - If it's different (like `10.x.x.x` or `172.x.x.x`), device is on different network

2. **Verify Same Network:**
   - iPhone IP should be: `192.168.0.XXX` (where XXX is 1-254)
   - Server IP is: `192.168.0.121`
   - If iPhone is on different subnet, it can't reach the server

### Step 2: Test Connectivity from iPhone

**Option A: Using Safari on iPhone**
1. Open Safari on iPhone
2. Navigate to: `http://192.168.0.121/api/health`
3. Should see JSON response: `{"status":"healthy",...}`
4. If this fails, network connectivity issue

**Option B: Using Terminal (if iPhone connected via USB)**
```bash
# Get device IP
ideviceinfo -u <UDID> | grep WiFiAddress

# Or check via Xcode
# Window → Devices and Simulators → Select iPhone → Network section
```

### Step 3: Check URLSession Configuration

**Current Issue:**
- `HaloAPIService` uses `URLSession.shared` (default configuration)
- Default timeout might be too short
- No explicit network interface selection
- No `waitsForConnectivity` setting

**Other services use custom config:**
- `TLSLayer2MessagingService` has custom config with:
  - `waitsForConnectivity = true`
  - `timeoutIntervalForRequest = 20`
  - `timeoutIntervalForResource = 40`

---

## Potential Issues

### Issue 1: Device on Different Network
**Symptom:** iPhone IP is not `192.168.0.x`
**Fix:** Connect iPhone to same WiFi network as server

### Issue 2: URLSession Default Timeout Too Short
**Symptom:** Requests timeout before server responds
**Fix:** Configure URLSession with longer timeouts

### Issue 3: Network Interface Selection
**Symptom:** iOS might be trying wrong network interface
**Fix:** Explicitly configure URLSession for local network

### Issue 4: Firewall on Server
**Symptom:** Server accessible from Mac but not iPhone
**Fix:** Check UFW firewall rules on server

---

## Next Steps

1. **Check iPhone IP address** (Settings → Wi-Fi)
2. **Test from Safari** on iPhone: `http://192.168.0.121/api/health`
3. **Share results** so we can determine:
   - Is device on same network?
   - Can device reach server at all?
   - Is it a URLSession configuration issue?

---

## Quick Fix to Try

If device is on same network, we should:
1. Configure URLSession with proper timeouts
2. Add `waitsForConnectivity = true`
3. Possibly use custom URLSession instead of shared

Let me know the iPhone's IP address and whether Safari can reach the server, then we can apply the appropriate fix.


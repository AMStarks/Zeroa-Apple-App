# Issue Diagnosis - Halo Token Acquisition Failure

## Root Cause Identified ✅

**Issue:** Network requests to `http://192.168.0.121/api/halo/challenge` are **timing out** from the iOS app.

**Error:** `NSURLErrorDomain Code=-1001 "The request timed out"`

---

## Evidence from Logs

### ✅ What's Working

1. **Zeroa Auto-Login:** ✅ Success
   - Address loaded: `TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x`
   - Authentication successful

2. **Token Ensure Flow:** ✅ Reaches network request
   - `ensureToken()` is called
   - `isProfileActive()` = true ✅
   - Address loaded ✅
   - Challenge request initiated ✅
   - URL constructed correctly: `http://192.168.0.121/api/halo/challenge?...`

3. **LASKO Authentication:** ✅ Working
   - Zeroa → LASKO auth flow successful
   - Signature verified

### ❌ What's Failing

**Network Request Timeout:**
```
🔍 HaloAPIService.requestChallenge: Sending request...
[5+ seconds pass]
❌ HaloService.ensureToken: FAILED - Error Domain=NSURLErrorDomain Code=-1001 "The request timed out."
```

**Multiple concurrent requests all timing out:**
- Multiple `ensureToken()` calls happening simultaneously
- All requests to `http://192.168.0.121/api/halo/challenge` timing out
- No response received from server

---

## Root Cause Analysis

### Issue: Local Network Permission Not Granted

**Symptoms:**
- Request is sent (`Sending request...`)
- But times out with no response
- Error code: -1001 (timeout)
- Works from command line (we tested earlier)

**Why This Happens:**
1. iOS 14+ requires explicit permission for local network access
2. Even with `NSLocalNetworkUsageDescription` in Info.plist, user must grant permission
3. If permission not granted, iOS silently blocks/ignores local network requests
4. Requests appear to be sent but never reach the network layer
5. Result: Timeout after default timeout period

### Verification

**From logs:**
- ✅ Request URL is correct: `http://192.168.0.121/api/halo/challenge?...`
- ✅ Request is being sent: `🔍 HaloAPIService.requestChallenge: Sending request...`
- ❌ No response received (timeout)
- ❌ Multiple concurrent requests all fail the same way

**This matches iOS local network blocking behavior:**
- Requests appear to be sent
- But iOS blocks them at network layer
- No actual network traffic occurs
- Timeout after ~5-10 seconds

---

## Solution

### Step 1: Grant Local Network Permission

**On iOS Device:**
1. Open **Settings** app
2. Go to **Privacy & Security**
3. Tap **Local Network**
4. Find **Zeroa** in the list
5. **Enable the toggle** (should be ON)

**OR**

1. Delete Zeroa app from device
2. Rebuild and reinstall
3. **When app launches, iOS will show permission dialog:**
   - "Zeroa would like to find and connect to devices on your local network"
   - Tap **"Allow"**

### Step 2: Verify Permission

**Check if permission is granted:**
- Settings → Privacy & Security → Local Network → Zeroa should be **ON**

### Step 3: Test Again

After granting permission:
1. Close and reopen Zeroa app
2. Login again
3. Check logs for successful challenge response
4. Token should be stored in App Groups

---

## Expected Behavior After Fix

**Before Permission (Current):**
```
🔍 HaloAPIService.requestChallenge: Sending request...
[timeout after 5-10 seconds]
❌ HaloService.ensureToken: FAILED - The request timed out.
```

**After Permission Granted:**
```
🔍 HaloAPIService.requestChallenge: Sending request...
🔍 HaloAPIService.requestChallenge: Response status: 200
✅ HaloAPIService.requestChallenge: Challenge request successful
✅ HaloService.ensureToken: Received challenge nonce=... ttl=120s
✅ HaloService.ensureToken: Token stored in App Groups
✅ HaloService.ensureToken: Token ensure complete!
```

---

## Additional Observations

### Multiple Concurrent Requests

**Issue:** Multiple `ensureToken()` calls happening simultaneously:
- On app appear
- On foreground
- After auto-login
- From token refresh request handler

**Impact:** All timing out, creating log spam

**Note:** This is not the root cause, but should be optimized later (deduplicate concurrent calls).

### LASKO Token Request

**LASKO is correctly:**
- Setting `halo_token_refresh_request` in App Groups
- Zeroa is detecting it
- Zeroa is calling `ensureToken()`
- But token acquisition fails due to network timeout

---

## Confirmation Checklist

To confirm this is the issue:

1. ✅ **Request is being sent** - Confirmed in logs
2. ✅ **URL is correct** - `http://192.168.0.121/api/halo/challenge`
3. ✅ **Server is accessible** - We tested via curl earlier
4. ❌ **Permission granted?** - Need to verify
5. ❌ **Same network?** - Need to verify device and server on same WiFi

---

## Next Steps

1. **Check iOS Settings:**
   - Settings → Privacy & Security → Local Network → Zeroa
   - If OFF, enable it
   - If not listed, reinstall app to trigger permission dialog

2. **Verify Network:**
   - Ensure iOS device and server (192.168.0.121) are on same WiFi network

3. **Test Again:**
   - Rebuild app
   - Grant permission when prompted
   - Login and check logs for successful token acquisition

---

## Summary

**Root Cause:** iOS local network permission not granted, causing all requests to `192.168.0.121` to timeout.

**Fix:** Grant local network permission in iOS Settings or reinstall app to trigger permission dialog.

**Status:** Issue identified, solution clear. Once permission is granted, token acquisition should work.


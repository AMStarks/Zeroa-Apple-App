# iOS Network Connection Fix - Zeroa & LASKO

## Problem Diagnosis

### Issue 1: Local Network Access Blocked ❌
**Error:** `NSURLErrorDomain Code=-1009 "The Internet connection appears to be offline"`
**Root Cause:** Missing `NSLocalNetworkUsageDescription` in Info.plist

iOS 14+ requires explicit permission to access local network resources (like `192.168.0.121`). Without this permission, iOS blocks all local network connections.

### Issue 2: Halo Token Not Available ❌
**Error:** `❌ LASKO: fetchPosts aborted - no fresh Halo token for address TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x`

**Root Cause:** Zeroa can't connect to Halo API to get JWT token, so LASKO has no token to use.

### Issue 3: LASKO Auth Works ✅
**Status:** Zeroa → LASKO authentication flow is working correctly via App Groups.

---

## Fix Applied

### ✅ Added NSLocalNetworkUsageDescription

**Zeroa/Info.plist:**
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Zeroa needs access to your local network to connect to the Halo API server for authentication and blockchain services.</string>
```

**LASKO_AppInfo.plist:**
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>LASKO needs access to your local network to connect to the Halo API server for social media features.</string>
```

---

## Expected Behavior After Fix

### First Launch (After Rebuild)
1. iOS will show a permission dialog: "Zeroa would like to find and connect to devices on your local network"
2. User must tap "Allow" to enable local network access
3. Once allowed, Zeroa can connect to `http://192.168.0.121/api`

### Authentication Flow
1. ✅ Zeroa logs in with address/mnemonic
2. ✅ Zeroa requests Halo challenge from API
3. ✅ Zeroa verifies signature and receives JWT token
4. ✅ Zeroa stores token in App Groups
5. ✅ LASKO reads token from App Groups
6. ✅ LASKO can fetch posts with token

---

## Testing Steps

### 1. Rebuild Both Apps
```bash
# In Xcode, clean and rebuild:
# Product → Clean Build Folder (Shift+Cmd+K)
# Product → Build (Cmd+B)
```

### 2. Test Zeroa First
1. Launch Zeroa
2. **IMPORTANT:** When iOS shows "Zeroa would like to find and connect to devices on your local network" → Tap **"Allow"**
3. Login with address/mnemonic
4. Check logs for: `✅ HaloService: Token stored exp=...`
5. Verify token in App Groups (should see `halo_access_token`)

### 3. Test LASKO
1. Launch LASKO
2. **IMPORTANT:** When iOS shows "LASKO would like to find and connect to devices on your local network" → Tap **"Allow"**
3. Request Zeroa authentication
4. Check logs for: `✅ LASKO: Signature verified; identity established`
5. Verify posts load successfully

---

## Verification Commands

### Check if Permission is Set
```bash
# On device/simulator, check Info.plist includes the key
plutil -p /path/to/app/Info.plist | grep NSLocalNetworkUsageDescription
```

### Test API Connection from Device
```bash
# From device, test if API is reachable
# (This will only work after permission is granted)
curl http://192.168.0.121/api/health
```

---

## Additional Notes

### iOS Permission Behavior
- **First time:** User must explicitly allow
- **Subsequent launches:** Permission persists (no dialog)
- **Revoking:** User can revoke in Settings → Privacy & Security → Local Network

### ATS (App Transport Security)
The apps already have ATS exceptions for `192.168.0.121`:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>192.168.0.121</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

This is correct and allows HTTP (not HTTPS) connections to the local IP.

---

## Troubleshooting

### If Permission Dialog Doesn't Appear
1. Delete app from device/simulator
2. Rebuild and reinstall
3. Launch app - dialog should appear

### If Connection Still Fails After Permission
1. Check device and server are on same network
2. Verify server is accessible: `ping 192.168.0.121`
3. Check iOS Settings → Privacy & Security → Local Network → Verify app is enabled

### If Token Still Not Available
1. Check Zeroa logs for successful Halo API connection
2. Verify token is stored: Check App Groups for `halo_access_token`
3. Check token expiration: Token should be valid for 1 hour

---

## Status

- ✅ **Fixed:** Added `NSLocalNetworkUsageDescription` to both apps
- ⏳ **Pending:** Rebuild apps and test
- ⏳ **Pending:** User must grant local network permission on first launch

**Next Action:** Rebuild both apps in Xcode and test the authentication flow.


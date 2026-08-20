# Debug Logging Added - Halo Token Flow

## Summary

Added comprehensive debug logging throughout the Halo token acquisition flow to identify where the process is failing.

---

## Logging Points Added

### 1. **HaloService.ensureToken()** - Main Entry Point
**Location:** `Zeroa/HaloService.swift`

**Logs Added:**
- ✅ Start of token ensure process
- ✅ `isProfileActive()` check and result
- ✅ Wallet address check and loaded address
- ✅ Stored token check (if exists and is fresh)
- ✅ Challenge request initiation
- ✅ API baseURL being used
- ✅ Challenge received (nonce, TTL)
- ✅ Canonical message being signed
- ✅ Signature creation success/failure
- ✅ Public key hex (first 20 chars)
- ✅ Verification request to server
- ✅ Verification success and token details
- ✅ Token storage in App Groups
- ✅ Complete token ensure success
- ❌ Detailed error logging (URLError codes, descriptions)

### 2. **HaloAPIService.requestChallenge()** - API Request
**Location:** `Zeroa/HaloAPIService.swift`

**Logs Added:**
- ✅ Challenge request start (address, bundleId)
- ✅ Full URL being requested
- ✅ Request sending
- ✅ Response status codes (primary and fallback)
- ✅ Challenge request success

### 3. **HaloAPIService.storeToken()** - Token Storage
**Location:** `Zeroa/HaloAPIService.swift`

**Logs Added:**
- ✅ Token storage start
- ✅ App Groups defaults check
- ✅ Token length and expiration
- ✅ All keys being set
- ✅ Synchronization result

### 4. **AppGroupsService.isProfileActive()** - Profile Status
**Location:** `Zeroa/AppGroupsService.swift`

**Logs Added:**
- ✅ sharedDefaults availability
- ✅ Key existence check
- ✅ Actual value returned

### 5. **ZeroaApp.handleBackgroundHandshakes()** - Token Refresh Handler
**Location:** `Zeroa/ZeroaApp.swift`

**Logs Added:**
- ✅ Token refresh request check
- ✅ Refresh request found/not found

### 6. **ZeroaApp Lifecycle** - App State Changes
**Location:** `Zeroa/ZeroaApp.swift`

**Logs Added:**
- ✅ `onAppear` - when ensureToken is called
- ✅ `willEnterForeground` - when ensureToken is called

### 7. **ContentView Login Flow** - Authentication
**Location:** `Zeroa/ContentView.swift`

**Logs Added:**
- ✅ Manual login success
- ✅ Auto-login success
- ✅ `authManager.isAuthenticated` state change
- ✅ `ensureToken()` call after login

---

## What to Look For in Logs

### Expected Flow (Success)
```
🔍 ZeroaApp.onAppear: Calling HaloService.ensureToken()...
🔍 HaloService.ensureToken: Starting token ensure process...
🔍 HaloService.ensureToken: Checking isProfileActive()...
🔍 AppGroupsService.isProfileActive: Key 'profile_account_active' not found, returning true (default)
🔍 HaloService.ensureToken: isProfileActive() = true
✅ HaloService.ensureToken: Profile is active, continuing...
🔍 HaloService.ensureToken: Checking wallet address...
✅ HaloService.ensureToken: Address loaded: TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x
🔍 HaloService.ensureToken: Checking for stored token...
🔍 HaloService.ensureToken: No valid stored token found, requesting new token...
🔎 HaloService.ensureToken: Requesting challenge for address=... bundleId=...
🔍 HaloAPIService.requestChallenge: Starting challenge request
🔍 HaloAPIService.requestChallenge: Requesting URL: http://192.168.0.121/api/halo/challenge?...
✅ HaloAPIService.requestChallenge: Challenge request successful
✅ HaloService.ensureToken: Received challenge nonce=... ttl=120s
✅ HaloService.ensureToken: Signature created (len=...)
✍️ HaloService.ensureToken: Verifying signature with server...
✅ HaloService.ensureToken: Verification successful, received token
✅ HaloService.ensureToken: Token stored in App Groups (key: halo_access_token)
✅ HaloService.ensureToken: Token ensure complete!
```

### Failure Scenarios to Watch For

#### Scenario 1: Profile Inactive
```
❌ HaloService.ensureToken: BLOCKED - account marked inactive (isProfileActive=false)
🔍 AppGroupsService.isProfileActive: Key 'profile_account_active' = false
```
**Fix:** Set `profile_account_active = true` in App Groups

#### Scenario 2: No Address
```
❌ HaloService.ensureToken: BLOCKED - No TLS address loaded, abort ensureToken
```
**Fix:** Ensure wallet is loaded before calling ensureToken

#### Scenario 3: Network Error
```
❌ HaloService.ensureToken: FAILED - URLError code: -1009
❌ HaloService.ensureToken: Error details: The Internet connection appears to be offline.
```
**Fix:** Check local network permission in iOS Settings

#### Scenario 4: API Error
```
❌ HaloAPIService.requestChallenge: HTTP 404: ...
```
**Fix:** Check server is running and endpoint is correct

---

## Next Steps

1. **Rebuild Zeroa app** in Xcode
2. **Run app and login** with your address
3. **Check console logs** for the debug messages
4. **Identify where the flow stops:**
   - Does it reach `ensureToken()`?
   - Does `isProfileActive()` return true?
   - Is address loaded?
   - Does it attempt network request?
   - What error occurs (if any)?

5. **Share the logs** so we can identify the exact failure point

---

## Key Debug Markers

- 🔍 = Debug/Info message
- ✅ = Success/Continue
- ❌ = Error/Blocked
- 🔎 = Network request
- ✍️ = Signing operation
- 🔁 = Refresh/Retry operation

---

**All logging is now in place. Rebuild and test to see exactly where the token acquisition is failing.**


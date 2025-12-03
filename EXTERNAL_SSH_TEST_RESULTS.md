# External SSH Connection Test Results

## Test Performed

**Date:** 2025-11-25  
**Test From:** External Network (IP: 49.186.208.67)  
**Target:** Optimus Server (IP: 114.73.209.140)  
**Port Tested:** 2222

## Test Results

### ❌ Port 2222: **NOT ACCESSIBLE**

**Test Commands:**
```bash
nc -zv 114.73.209.140 2222
ssh -p 2222 chief@114.73.209.140
```

**Result:**
- Connection timeout
- No packets reaching server
- Router port forwarding **NOT ACTIVE**

### ✅ Server Configuration: **CORRECT**

- SSH listening on all interfaces (0.0.0.0:22)
- Firewall allows port 2222
- No iptables blocking
- fail2ban not blocking
- Service running correctly

## Root Cause Confirmed

**Router port forwarding rule is configured but NOT active.**

**Evidence:**
1. ✅ Server firewall allows connections
2. ✅ SSH service listening correctly
3. ❌ No packets reaching server on port 2222
4. ❌ External connection times out

## Required Actions

### 1. **Router Configuration**

**On Router (192.168.0.1):**

1. **Verify Port Forwarding Rule:**
   - External Port: 2222
   - Internal IP: 192.168.0.121
   - Internal Port: 22
   - Protocol: TCP
   - Status: **Enabled**

2. **Save/Apply Rule:**
   - Click **"Save"** or **"Apply"** button
   - Some routers require explicit save
   - Wait for confirmation message

3. **Restart Router:**
   - Power cycle or admin restart
   - Wait 2-3 minutes for full boot
   - Port forwarding activates on restart

4. **Check Router Firewall:**
   - Disable "Block WAN requests" if enabled
   - Allow external connections
   - Check for any firewall rules blocking port 2222

### 2. **Alternative: Test Port 22**

**If port 2222 doesn't work after router restart:**

1. **Create new rule:** Port 22 → 192.168.0.121:22
2. **Test:** `ssh -p 22 chief@114.73.209.140`
3. **Note:** Some ISPs block port 22, but worth trying

### 3. **Verify Port Forwarding**

**After router restart, test again:**

```bash
# From external network:
nc -zv 114.73.209.140 2222

# Should see:
# Connection to 114.73.209.140 port 2222 [tcp/*] succeeded!
```

**On server (while testing):**
```bash
sudo tcpdump -i eno1 -n 'tcp port 2222' -v

# Should see incoming packets if forwarding works
```

## Current Status

- ✅ **Server:** Fully configured and ready
- ❌ **Router:** Port forwarding not active
- ⚠️ **Action Required:** Save/apply rule and restart router

## Next Steps

1. **Save port forwarding rule** in router
2. **Restart router**
3. **Test again** from external network
4. **Monitor server** with tcpdump during test
5. **If still fails:** Try port 22 or check ISP blocking

## Alternative Solutions

If port forwarding continues to fail:

1. **Tailscale** - Easy VPN solution
2. **WireGuard** - Self-hosted VPN
3. **Cloudflare Tunnel** - No port forwarding needed


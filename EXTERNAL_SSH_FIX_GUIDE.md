# External SSH Connection Fix Guide

## Diagnosis Summary

### ✅ Server Configuration (All Correct)
- SSH listening on `0.0.0.0:22` (all interfaces)
- Firewall allows ports 22 and 2222
- No iptables NAT rules blocking
- fail2ban not blocking connections
- External IP: 114.73.209.140 (confirmed)

### ❌ Problem: Router Port Forwarding Not Working

**Evidence:**
- Port forwarding rule exists in router (2222 → 192.168.0.121:22)
- Server firewall allows connections
- **But:** No packets reaching port 2222 (0 packets in iptables)
- **Result:** Connection timeout from external network

## Root Cause

The router port forwarding rule is **configured but not active**. This is typically because:

1. **Rule not saved/applied** in router
2. **Router needs restart** to activate port forwarding
3. **Router firewall** blocking external connections
4. **ISP blocking** port 2222 (less common)

## Fix Steps

### Step 1: Verify Router Port Forwarding

**On Router Admin Panel (192.168.0.1):**

1. **Check rule status:**
   - Rule: Port 2222 → 192.168.0.121:22
   - Status should be **"Enabled"** ✅
   - **Action:** Click **"Save"** or **"Apply"** if available

2. **Check router firewall:**
   - Look for **"Firewall"** or **"Security"** section
   - Ensure **"Block WAN requests"** is **disabled**
   - Ensure **"Allow external connections"** is **enabled**

### Step 2: Restart Router

**After saving port forwarding:**
1. **Restart router** (power cycle or admin restart)
2. **Wait 2-3 minutes** for router to fully boot
3. **Test connection** from external network

### Step 3: Test Port Forwarding

**From external network (not your local network):**
```bash
# Test port connectivity
nc -zv 114.73.209.140 2222

# If port is open, you'll see:
# Connection to 114.73.209.140 port 2222 [tcp/*] succeeded!
```

**Or use online tool:**
- https://www.yougetsignal.com/tools/open-ports/
- Enter: 114.73.209.140, Port: 2222

### Step 4: Monitor Server for Connections

**On Optimus (while testing from external network):**
```bash
# Monitor for incoming connections
sudo tcpdump -i eno1 -n 'tcp port 2222' -v

# If you see packets, port forwarding is working!
# If no packets, router forwarding is not active
```

### Step 5: Alternative - Use Port 22

**If port 2222 doesn't work, try port 22:**

1. **Router rule:** Port 22 → 192.168.0.121:22
2. **Test:** `ssh -p 22 chief@114.73.209.140`
3. **Note:** Some ISPs block port 22, but worth trying

## Common Router Issues

### Issue 1: Rule Not Saved
**Symptom:** Rule shows in UI but doesn't work
**Fix:** Click "Save" or "Apply" button explicitly

### Issue 2: Router Firewall Blocking
**Symptom:** Port forwarding configured but blocked
**Fix:** Disable router firewall or add exception

### Issue 3: ISP Blocking
**Symptom:** Port forwarding works but ISP blocks port
**Fix:** Use different port (8022, 22022, etc.)

### Issue 4: CGNAT (Carrier-Grade NAT)
**Symptom:** Multiple routers/NAT layers
**Fix:** Use VPN solution (Tailscale, WireGuard)

## Verification Commands

### On Optimus (Server):
```bash
# Monitor for incoming connections
sudo tcpdump -i eno1 -n 'tcp port 2222' -v

# Check firewall status
sudo ufw status verbose

# Check SSH service
sudo systemctl status sshd
```

### From External Network:
```bash
# Test port
nc -zv 114.73.209.140 2222

# Test SSH
ssh -v -p 2222 chief@114.73.209.140
```

## Expected Results

### If Port Forwarding Works:
- `nc` command succeeds
- `tcpdump` shows incoming packets
- SSH connection establishes

### If Port Forwarding Doesn't Work:
- `nc` command times out
- `tcpdump` shows no packets
- SSH connection times out

## Next Steps

1. **Save/Apply** port forwarding rule in router
2. **Restart router**
3. **Test from external network** (not local network)
4. **Monitor server** with tcpdump during test
5. **If still fails:** Try port 22 or different port

## Alternative Solutions

If port forwarding continues to fail:

1. **Tailscale** - Easy VPN (recommended)
   - Install on Optimus and your Mac
   - No port forwarding needed
   - Works through firewalls/NAT

2. **WireGuard** - Self-hosted VPN
   - More setup required
   - Full control

3. **Cloudflare Tunnel** - No port forwarding
   - Free tier available
   - Works through any firewall

## Current Status

- ✅ Server ready (firewall, SSH, all configured)
- ❌ Router port forwarding not active
- ⚠️ Need to save/apply rule and restart router

**Action Required:** Configure router port forwarding properly, then test from external network.


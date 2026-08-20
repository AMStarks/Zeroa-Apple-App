# External SSH Connection Diagnosis

## Current Status

### ✅ Server-Side Configuration (All Correct)

1. **SSH Service**
   - ✅ Listening on `0.0.0.0:22` (all interfaces)
   - ✅ IPv4 and IPv6 enabled
   - ✅ Service running (PID 23962)

2. **Firewall (UFW)**
   - ✅ Port 22: ALLOW IN from Anywhere
   - ✅ Port 2222: ALLOW IN from Anywhere
   - ✅ IPv6 rules also configured

3. **iptables**
   - ✅ Port 22: ACCEPT (22 packets, 1408 bytes)
   - ✅ Port 2222: ACCEPT (0 packets - no connections yet)

4. **fail2ban**
   - ✅ Not blocking any IPs
   - ✅ No failed attempts logged

5. **SSH Configuration**
   - ✅ Port 22 (default, commented out = uses default)
   - ✅ ListenAddress not restricted (commented out = listens on all)

### ❌ External Connection Test

- **External IP:** 114.73.209.140
- **Port:** 2222
- **Result:** Connection timeout
- **Local IP:** 192.168.0.121
- **Gateway:** 192.168.0.1

## Root Cause Analysis

### Issue: Router Port Forwarding Not Active

**Evidence:**
1. ✅ Server firewall allows port 2222
2. ✅ SSH service listening on all interfaces
3. ✅ No connections reaching port 2222 (0 packets in iptables)
4. ❌ External connection times out

**Conclusion:** The router port forwarding rule exists but is **not active** or **not properly configured**.

## Router Configuration Check

From your router screenshot, I can see:
- **Rule exists:** Port 2222 → 192.168.0.121:22
- **Status:** Enabled
- **But:** Connection still times out

### Possible Issues:

1. **Router needs restart** to apply port forwarding
2. **Router firewall** blocking external connections
3. **ISP blocking** port 2222 (some ISPs block non-standard ports)
4. **Port forwarding rule** not saved/applied correctly
5. **Router firmware bug** - rule exists but not working

## Diagnostic Steps

### 1. Verify Router Port Forwarding

**On Router Admin Panel:**
- Check if rule is **saved** (not just configured)
- Look for **"Apply"** or **"Save"** button
- Check if router needs **restart**

### 2. Test Port Forwarding

**From external network:**
```bash
# Test if port is reachable
nc -zv 114.73.209.140 2222

# Or use online tool:
# https://www.yougetsignal.com/tools/open-ports/
```

### 3. Check Router Firewall

**On Router Admin Panel:**
- Look for **"Firewall"** or **"Security"** settings
- Ensure external connections are allowed
- Check for **"Block WAN requests"** setting (should be disabled)

### 4. Test Different Port

**Try port 22 instead of 2222:**
- Some ISPs block port 22
- Port 2222 is less likely to be blocked
- But router might handle 22 differently

### 5. Check ISP Blocking

**Some ISPs block:**
- Port 22 (SSH)
- Port 2222 (less common)
- All incoming connections (CGNAT)

**Test:**
- Try from different external network
- Use mobile hotspot
- Check if other ports work (80, 443)

## Recommended Fixes

### Option 1: Restart Router
1. Save port forwarding rule
2. Restart router
3. Wait 2-3 minutes
4. Test connection

### Option 2: Use Port 22 Instead
1. Change router rule: Port 22 → 192.168.0.121:22
2. Test: `ssh -p 22 chief@114.73.209.140`
3. **Note:** Some ISPs block port 22

### Option 3: Check Router Firewall
1. Disable router firewall temporarily
2. Test connection
3. If works, configure firewall rules properly

### Option 4: Use Different External Port
1. Try port 8022 or 22022 (less likely blocked)
2. Update router rule
3. Test connection

### Option 5: Verify ISP/CGNAT
1. Check if you're behind CGNAT (carrier-grade NAT)
2. If yes, you'll need:
   - VPN solution
   - Port forwarding service
   - Or use different connection method

## Quick Test Commands

### From External Network:
```bash
# Test port connectivity
nc -zv 114.73.209.140 2222

# Test SSH (will timeout if port forwarding not working)
ssh -v -p 2222 chief@114.73.209.140
```

### From Router/Server:
```bash
# On Optimus, monitor for incoming connections
sudo tcpdump -i any -n 'tcp port 2222' -v

# Then try connecting externally - if you see packets, forwarding works
```

## Most Likely Issue

**Router port forwarding rule is not active/applied.**

**Solution:**
1. **Save/Apply** the port forwarding rule in router
2. **Restart router** to ensure rules are active
3. **Test again** from external network

If still doesn't work:
- Check router firewall settings
- Try different external port
- Verify ISP isn't blocking

## Alternative: Use VPN or Tailscale

If port forwarding continues to fail:
- **Tailscale** - Easy VPN solution
- **WireGuard** - Self-hosted VPN
- **Cloudflare Tunnel** - No port forwarding needed


# Optimus External Port Access Analysis

**Date:** 2025-11-27  
**Issue:** Cannot connect to Optimus via SSH externally  
**Status:** Ports 22 and 2222 timing out, but ports 80/443 working

---

## Evidence Summary

### ✅ What's Working (Proves Server is Up)

1. **HTTPS API (Port 443)**
   - `curl https://halo.telestai.io/api/health` → `{"ok":true}`
   - **Conclusion:** Port forwarding for 443 is active

2. **HTTP API (Port 80)**
   - API endpoints responding
   - **Conclusion:** Port forwarding for 80 is active

3. **DNS Resolution**
   - `halo.telestai.io` → `114.73.209.140`
   - **Conclusion:** DNS is correct

4. **RPC Proxy**
   - `https://halo.telestai.io/api/tls/rpc` → Working (block count: 687507)
   - **Conclusion:** Server services are operational

### ❌ What's Not Working

1. **SSH Port 22**
   - `ssh -p 22 chief@114.73.209.140` → `Operation timed out`
   - `nc -zv 114.73.209.140 22` → `Connection timed out`

2. **SSH Port 2222**
   - `ssh -p 2222 chief@114.73.209.140` → `Operation timed out`
   - `nc -zv 114.73.209.140 2222` → `Connection timed out`

3. **ICMP (Ping)**
   - `ping 114.73.209.140` → `100% packet loss`
   - **Note:** This is normal - many routers/firewalls block ICMP

---

## Root Cause Analysis

### Primary Issue: Router Port Forwarding Configuration

**Key Evidence:**
- ✅ Ports 80/443 work → Router forwarding is functional
- ❌ Ports 22/2222 don't work → SSH forwarding is missing/inactive
- ✅ Server is up (API responding) → Not a server issue
- ✅ SSH key exists → Not an authentication issue

**Conclusion:** The router port forwarding rule for SSH (port 2222 → 192.168.0.121:22) was removed, disabled, or reset.

### Why This Happened

**Most Likely Scenarios:**

1. **Router Reset/Update**
   - Router firmware update reset configuration
   - Power outage caused router to lose non-persistent settings
   - Router factory reset (intentional or accidental)

2. **Port Forwarding Rule Deleted**
   - Someone accessed router admin and removed the rule
   - Router interface bug cleared the rule
   - Router configuration file corrupted

3. **Router Replaced/Changed**
   - New router installed
   - Router settings migrated but port forwarding wasn't included
   - Router IP address changed (unlikely - API still works)

### Why HTTP/HTTPS Still Works

**Possible Explanations:**

1. **Different Port Forwarding Rules**
   - HTTP/HTTPS rules are separate from SSH rules
   - Only SSH rule was affected
   - HTTP/HTTPS rules are more persistent (DMZ or different config section)

2. **UPnP/NAT-PMP**
   - Some services use UPnP for automatic port mapping
   - HTTP/HTTPS might be using automatic mapping
   - SSH requires manual port forwarding

3. **Router Configuration Priority**
   - HTTP/HTTPS rules might be in a different section (Virtual Server vs Port Forwarding)
   - Some routers have separate config files for different services

---

## Detailed Port Analysis

### Port 22 (Standard SSH)

**Status:** ❌ Not accessible externally

**Expected Configuration:**
- External Port: 22
- Internal IP: 192.168.0.121
- Internal Port: 22
- Protocol: TCP

**Why It's Not Working:**
- No port forwarding rule exists
- OR rule exists but is disabled
- OR router is blocking port 22 (some ISPs block this)

**Historical Note:**
- Port 22 was never configured for external access
- Only port 2222 was used (per EXTERNAL_SSH_SUCCESS.md)

### Port 2222 (Alternative SSH)

**Status:** ❌ Not accessible externally (was working on 2025-11-25)

**Expected Configuration:**
- External Port: 2222
- Internal IP: 192.168.0.121
- Internal Port: 22
- Protocol: TCP

**Why It's Not Working:**
- Port forwarding rule was removed/reset
- This is the port that was working before

**Historical Note:**
- ✅ Was working on 2025-11-25
- ✅ Connection successful: `ssh -i ~/.ssh/id_optimus -p 2222 chief@114.73.209.140`
- ❌ Now timing out

### Port 80 (HTTP)

**Status:** ✅ Working

**Configuration:**
- External Port: 80
- Internal IP: 192.168.0.121
- Internal Port: 80
- Protocol: TCP

**Why It's Working:**
- Port forwarding rule is active
- OR using UPnP/NAT-PMP
- OR configured in different router section

### Port 443 (HTTPS)

**Status:** ✅ Working

**Configuration:**
- External Port: 443
- Internal IP: 192.168.0.121
- Internal Port: 443
- Protocol: TCP

**Why It's Working:**
- Port forwarding rule is active
- OR using UPnP/NAT-PMP
- OR configured in different router section

---

## Network Topology Analysis

```
Internet
   │
   │ (External IP: 114.73.209.140)
   │
Router (192.168.0.1)
   │
   ├─ Port 80/443 → 192.168.0.121:80/443 ✅ WORKING
   │
   └─ Port 2222 → 192.168.0.121:22 ❌ MISSING/BROKEN
       │
       └─ Optimus (192.168.0.121)
           ├─ SSH Service (port 22) ✅ Running
           ├─ Nginx (ports 80/443) ✅ Running
           └─ Halo API (port 3001) ✅ Running
```

**Problem:** The router is not forwarding external port 2222 to internal 192.168.0.121:22

---

## What Needs to Be Fixed

### Required Action: Reconfigure Router Port Forwarding

**Router Admin Access:**
- Router IP: `192.168.0.1` (or check with `ip route | grep default`)
- Access via: `http://192.168.0.1` or `https://192.168.0.1`

**Port Forwarding Rule to Create:**

| Setting | Value |
|---------|-------|
| **Service Name** | SSH-Optimus |
| **External Port** | 2222 |
| **Internal IP** | 192.168.0.121 |
| **Internal Port** | 22 |
| **Protocol** | TCP |
| **Status** | Enabled |

**Alternative (if 2222 doesn't work):**
- Use port 22222 or another high port (some ISPs block low ports)
- Update SSH config on server to listen on that port

---

## Verification Steps (After Fix)

### Step 1: Test Port Connectivity

```bash
# From external network (mobile hotspot)
nc -zv -w 5 114.73.209.140 2222
```

**Expected:** `Connection to 114.73.209.140 port 2222 [tcp] succeeded!`

### Step 2: Test SSH Connection

```bash
ssh -i ~/.ssh/id_optimus -p 2222 -v chief@114.73.209.140
```

**Expected:** Successful connection and authentication

### Step 3: Verify Server Access

```bash
ssh -i ~/.ssh/id_optimus -p 2222 chief@114.73.209.140 "hostname && uptime"
```

**Expected:** Output showing "Optimus" and uptime

---

## Why This Matters

### Impact on Current Work

**Transaction Signing Fix:**
- ✅ Can still test via API (no SSH needed)
- ✅ Can verify transactions work
- ❌ Cannot check server logs directly
- ❌ Cannot update server configuration
- ❌ Cannot debug server-side issues

**Priority:** Medium
- Server is operational
- API is working
- SSH is convenience feature for administration

### When SSH Access is Critical

- Server logs need checking
- Configuration changes needed
- Service restarts required
- Debugging server-side issues
- Updating server software

---

## Prevention for Future

### Recommendations

1. **Document Router Configuration**
   - Take screenshots of port forwarding rules
   - Export router configuration if possible
   - Keep backup of router settings

2. **Use Persistent Configuration**
   - Some routers have "save to file" option
   - Document all port forwarding rules
   - Keep router firmware updated (but test after updates)

3. **Monitor Port Status**
   - Set up automated port checking
   - Alert if SSH port becomes unreachable
   - Use monitoring service (UptimeRobot, etc.)

4. **Alternative Access Methods**
   - Set up VPN for secure access
   - Use cloud-based access (Tailscale, ZeroTier)
   - Configure multiple SSH ports as backup

---

## Summary

**Problem:** External SSH access to Optimus is not working  
**Root Cause:** Router port forwarding rule for port 2222 → 192.168.0.121:22 is missing or disabled  
**Evidence:** Ports 80/443 work (proving router forwarding works), but 22/2222 don't  
**Server Status:** ✅ Fully operational (API working)  
**Fix Required:** Reconfigure router port forwarding for SSH  
**Priority:** Medium (server is functional, SSH is administrative convenience)

**Next Action:** When you get home, access router admin panel and recreate the port forwarding rule for SSH.


# Optimus SSH Connection Diagnostic

**Date:** 2025-11-27  
**Status:** ❌ SSH connection failing, but server is operational  
**API Status:** ✅ Working (HTTPS endpoints responding)

---

## Current Status

### ✅ What's Working

1. **Server is UP and Running**
   - API health check: `https://halo.telestai.io/api/health` → `{"ok":true}`
   - RPC proxy: `https://halo.telestai.io/api/tls/rpc` → Responding (block count: 687507)
   - Services operational: API and Redis confirmed working

2. **HTTPS/HTTP Access**
   - Port 80 (HTTP): Accessible
   - Port 443 (HTTPS): Accessible
   - DNS resolution: `halo.telestai.io` → `114.73.209.140` ✅

### ❌ What's Not Working

1. **SSH Port 22**
   - Connection: `ssh -i ~/.ssh/id_optimus -p 22 chief@114.73.209.140`
   - Result: `Operation timed out`
   - Status: Port not accessible externally

2. **SSH Port 2222**
   - Connection: `ssh -i ~/.ssh/id_optimus -p 2222 chief@114.73.209.140`
   - Result: `Operation timed out`
   - Status: Port not accessible externally

3. **ICMP (Ping)**
   - Connection: `ping 114.73.209.140`
   - Result: `100% packet loss`
   - Status: ICMP blocked (normal security practice)

---

## Historical Context

### Previous Working Configuration

According to `EXTERNAL_SSH_SUCCESS.md` (2025-11-25):
- ✅ Port 2222 was working externally
- ✅ SSH authentication successful
- ✅ Router port forwarding was active:
  - External Port: 2222
  - Internal IP: 192.168.0.121
  - Internal Port: 22

**Connection command that worked:**
```bash
ssh -i ~/.ssh/id_optimus -p 2222 chief@114.73.209.140
```

---

## Root Cause Analysis

### Most Likely Cause: Router Port Forwarding Reset

**Evidence:**
1. API (ports 80/443) still works → Router forwarding for HTTP/HTTPS is active
2. SSH (ports 22/2222) doesn't work → Router forwarding for SSH is missing/inactive
3. Server is definitely up (API responding)
4. SSH key exists and is valid (`~/.ssh/id_optimus` present)

**Conclusion:** Router port forwarding for SSH ports was likely reset or changed.

### Other Possible Causes (Less Likely)

1. **Server Firewall Changed**
   - UFW might have been reconfigured
   - fail2ban might be blocking connections
   - SSH service might have stopped

2. **Network Configuration Changed**
   - Router IP address changed
   - Server internal IP changed (currently 192.168.0.121)
   - ISP blocking SSH ports

3. **SSH Service Issue**
   - SSH daemon not listening on external interface
   - SSH service crashed/stopped

---

## Diagnostic Steps (When You Get Home)

### Step 1: Verify Server is Accessible Locally

**If you're on the same local network (192.168.0.x):**

```bash
# Test local SSH access
ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 "echo 'Local SSH works'"

# Check if server is up
ping -c 3 192.168.0.121

# Check SSH service status
ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 "sudo systemctl status sshd"
```

**Expected Results:**
- ✅ Local SSH should work if server is on same network
- ✅ Ping should work locally
- ✅ SSH service should be active

### Step 2: Check Router Port Forwarding

**Access router admin panel (usually 192.168.0.1 or 192.168.1.1):**

1. **Check existing port forwarding rules:**
   - Look for rules forwarding port 2222 → 192.168.0.121:22
   - Look for rules forwarding port 22 → 192.168.0.121:22

2. **Verify or recreate port forwarding:**
   - **Service Name:** SSH-Optimus
   - **External Port:** 2222 (or 22)
   - **Internal IP:** 192.168.0.121
   - **Internal Port:** 22
   - **Protocol:** TCP

3. **Check if router has been reset:**
   - Router firmware updates can reset port forwarding
   - Power outages can reset router configuration
   - Factory resets clear all port forwarding

### Step 3: Test External SSH Access

**From external network (or using mobile hotspot):**

```bash
# Test port 2222
nc -zv -w 5 114.73.209.140 2222

# Test port 22
nc -zv -w 5 114.73.209.140 22

# Try SSH connection
ssh -i ~/.ssh/id_optimus -p 2222 -v chief@114.73.209.140
```

**Expected Results:**
- ✅ Port should be open if forwarding is configured
- ✅ SSH should connect if port is open

### Step 4: Check Server Firewall (If Local Access Works)

**If local SSH works, check server firewall:**

```bash
ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 << 'EOF'
# Check UFW status
sudo ufw status verbose

# Check if ports 22 and 2222 are open
sudo ufw status | grep -E "(22|2222)"

# Check SSH service status
sudo systemctl status sshd --no-pager

# Check SSH listening ports
sudo netstat -tlnp | grep sshd
# or
sudo ss -tlnp | grep sshd

# Check fail2ban status
sudo fail2ban-client status sshd
EOF
```

**Expected Results:**
- ✅ UFW should show ports 22/2222 open
- ✅ SSH service should be active
- ✅ SSH should be listening on 0.0.0.0:22 (all interfaces)
- ✅ fail2ban should not be blocking your IP

### Step 5: Verify Router External IP

**Check if router external IP changed:**

```bash
# From server
ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 "curl -s ifconfig.me"

# Should return: 114.73.209.140
```

**If IP changed:**
- Update DNS records if using dynamic DNS
- Update any firewall rules referencing old IP

---

## Quick Fix Checklist

When you get home, follow this order:

- [ ] **1. Test local SSH access** (if on same network)
  ```bash
  ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121
  ```

- [ ] **2. Check router port forwarding**
  - Log into router admin (192.168.0.1)
  - Verify port 2222 → 192.168.0.121:22 exists
  - If missing, create the rule

- [ ] **3. Test external SSH** (from mobile hotspot or different network)
  ```bash
  ssh -i ~/.ssh/id_optimus -p 2222 chief@114.73.209.140
  ```

- [ ] **4. If still failing, check server firewall** (via local access)
  ```bash
  ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 "sudo ufw status"
  ```

- [ ] **5. Verify SSH service is running** (via local access)
  ```bash
  ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 "sudo systemctl status sshd"
  ```

---

## Current Working Configuration

### SSH Key
- **Location:** `~/.ssh/id_optimus`
- **Status:** ✅ Present and readable
- **Permissions:** `-rw-------` (correct)

### Server Details
- **Hostname:** Optimus
- **Internal IP:** 192.168.0.121
- **External IP:** 114.73.209.140
- **SSH User:** chief
- **SSH Port:** 22 (internal), 2222 (external forwarding)

### API Endpoints (Working)
- **Health:** `https://halo.telestai.io/api/health`
- **RPC Proxy:** `https://halo.telestai.io/api/tls/rpc`
- **Status:** ✅ All responding correctly

---

## Impact Assessment

### What This Affects

❌ **Cannot do:**
- Direct SSH access to server
- Server administration via SSH
- Running diagnostic commands on server
- Checking logs directly
- Updating server configuration

✅ **Can still do:**
- Use API endpoints (all working)
- Test iOS app functionality
- Test transaction signing (via API)
- Monitor API health
- Use RPC proxy for blockchain operations

### Workaround

If you need server access urgently:
1. Use local network access (if on same network)
2. Use VPN if available
3. Use alternative access method (console, VNC, etc.)

---

## Next Steps

1. **Immediate:** Continue testing transaction signing via API (no SSH needed)
2. **When home:** Follow diagnostic steps above to restore SSH access
3. **Prevention:** Document router configuration or set up dynamic DNS monitoring

---

## Summary

**Problem:** SSH ports (22 and 2222) are not accessible externally  
**Root Cause:** Most likely router port forwarding reset or changed  
**Server Status:** ✅ Operational (API working)  
**Impact:** Cannot SSH into server, but all API functionality works  
**Fix Required:** Reconfigure router port forwarding for SSH ports

**Priority:** Medium (server is operational, SSH is convenience feature)


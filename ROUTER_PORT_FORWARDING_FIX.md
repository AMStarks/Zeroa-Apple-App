# Router Port Forwarding Fix - Step by Step Guide

**Date:** 2025-11-27  
**Issue:** SSH port 2222 not accessible externally  
**Fix:** Reconfigure router port forwarding

---

## Quick Start

1. **Run the diagnostic script:**
   ```bash
   ./fix_optimus_ssh.sh
   ```

2. **If SSH is still not working, follow the steps below**

---

## Step-by-Step Router Configuration

### Step 1: Access Router Admin Panel

1. **Open a web browser** (Chrome, Safari, Firefox, etc.)

2. **Navigate to router IP:**
   ```
   http://192.168.0.1
   ```
   OR
   ```
   http://192.168.1.1
   ```
   (Check router label if neither works)

3. **Log in:**
   - Username: Usually `admin` or blank
   - Password: Check router label or documentation
   - Common defaults: `admin/admin` or `admin/password`

### Step 2: Find Port Forwarding Section

**Look for one of these menu items** (varies by router brand):

- **Port Forwarding**
- **Virtual Server**
- **NAT Forwarding**
- **Firewall Rules**
- **Applications & Gaming**
- **Advanced → Port Forwarding**

**Common locations:**
- **Netgear:** Advanced → Port Forwarding / Port Triggering
- **TP-Link:** Advanced → NAT Forwarding → Virtual Servers
- **Linksys:** Connectivity → Port Forwarding
- **ASUS:** WAN → Virtual Server / Port Forwarding
- **D-Link:** Advanced → Port Forwarding

### Step 3: Add Port Forwarding Rule

**Click "Add" or "Create New Rule"** and enter:

| Field | Value |
|-------|-------|
| **Service Name** | `SSH-Optimus` |
| **External Port** | `2222` |
| **Internal IP** | `192.168.0.121` |
| **Internal Port** | `22` |
| **Protocol** | `TCP` (or `Both`/`TCP/UDP`) |
| **Status** | `Enabled` |

**Important Notes:**
- External Port and Internal Port can be different (2222 → 22)
- Make sure Internal IP matches Optimus server (192.168.0.121)
- Protocol must include TCP (SSH uses TCP)

### Step 4: Save and Apply

1. **Click "Save"** or "Apply"
2. **Wait 1-2 minutes** - Router may restart
3. **Don't close browser** until configuration is saved

### Step 5: Verify Configuration

**Check the port forwarding list shows:**
- ✅ Service: SSH-Optimus
- ✅ External Port: 2222
- ✅ Internal IP: 192.168.0.121
- ✅ Internal Port: 22
- ✅ Status: Enabled

---

## Testing After Configuration

### Option 1: Use the Script

```bash
./fix_optimus_ssh.sh
```

### Option 2: Manual Test

**From external network (use mobile hotspot):**

```bash
# Test port connectivity
nc -zv -w 5 114.73.209.140 2222

# Test SSH connection
ssh -i ~/.ssh/id_optimus -p 2222 chief@114.73.209.140
```

**Expected Results:**
- ✅ Port test: `Connection succeeded!`
- ✅ SSH: Successful connection and authentication

---

## Troubleshooting

### Issue: Can't Access Router Admin

**Solutions:**
1. **Check router IP:**
   ```bash
   # On Mac
   netstat -nr | grep default
   # Look for gateway IP (usually 192.168.0.1 or 192.168.1.1)
   ```

2. **Try different browsers** (some routers have compatibility issues)

3. **Check router label** for default IP and credentials

4. **Reset router** (last resort - will lose all settings)

### Issue: Port Forwarding Section Not Found

**Solutions:**
1. **Check router manual** (PDF usually available on manufacturer website)

2. **Look for "Advanced" or "Expert" mode** - some routers hide port forwarding there

3. **Search router admin interface** for "port" or "forward"

4. **Check if router supports port forwarding** (some basic routers don't)

### Issue: Rule Saved But Still Not Working

**Checklist:**
- [ ] Router has restarted (wait 2-3 minutes)
- [ ] External IP is still 114.73.209.140 (check with `curl ifconfig.me` from server)
- [ ] Testing from external network (not local network)
- [ ] Server firewall allows port 22 (should already be configured)
- [ ] SSH service is running on server (check via local access)

**Test from different network:**
- Use mobile hotspot
- Use different WiFi network
- Use VPN to different location

### Issue: Router Keeps Resetting Port Forwarding

**Solutions:**
1. **Update router firmware** (may fix bugs)

2. **Save configuration to file** (if router supports it)

3. **Check router logs** for errors

4. **Consider router replacement** if it's old/unreliable

---

## Alternative: Use Different Port

**If port 2222 doesn't work, try a high port:**

1. **Choose a high port** (e.g., 22222, 22223)

2. **Update router port forwarding:**
   - External Port: `22222`
   - Internal Port: `22`

3. **Update SSH config on server** (if needed):
   ```bash
   # On Optimus server
   sudo nano /etc/ssh/sshd_config
   # Add: Port 22222
   # Or keep Port 22 and just forward 22222 → 22
   ```

4. **Test with new port:**
   ```bash
   ssh -i ~/.ssh/id_optimus -p 22222 chief@114.73.209.140
   ```

---

## Verification Checklist

After configuring, verify:

- [ ] Router port forwarding rule exists and is enabled
- [ ] External port test succeeds: `nc -zv 114.73.209.140 2222`
- [ ] SSH connection works: `ssh -i ~/.ssh/id_optimus -p 2222 chief@114.73.209.140`
- [ ] Can run commands: `ssh ... "hostname && uptime"`
- [ ] Script reports success: `./fix_optimus_ssh.sh`

---

## Security Reminders

⚠️ **Important Security Notes:**

1. **SSH Key Authentication** ✅ Already configured
2. **Root Login Disabled** ✅ Already configured
3. **Strong Passwords** ✅ Ensure password auth is secure if enabled
4. **Consider Non-Standard Port** ✅ Using 2222 instead of 22 (good)
5. **Monitor Access Logs** - Check `/var/log/auth.log` periodically

---

## Quick Reference

**Router Admin:** `http://192.168.0.1`  
**Optimus Internal IP:** `192.168.0.121`  
**External IP:** `114.73.209.140`  
**SSH Port:** `2222`  
**SSH User:** `chief`  
**SSH Key:** `~/.ssh/id_optimus`

**Connection Command:**
```bash
ssh -i ~/.ssh/id_optimus -p 2222 chief@114.73.209.140
```

---

## Next Steps After Fix

Once SSH is working:

1. ✅ Verify server status
2. ✅ Check service logs
3. ✅ Test transaction signing fix
4. ✅ Update server if needed
5. ✅ Document router configuration (take screenshots)

---

## Support

If you're still having issues after following this guide:

1. **Check router manufacturer support** (they may have specific instructions)
2. **Review router logs** for blocked connections
3. **Test with different port** (22222, 22223, etc.)
4. **Consider VPN alternative** (Tailscale, ZeroTier) for easier access


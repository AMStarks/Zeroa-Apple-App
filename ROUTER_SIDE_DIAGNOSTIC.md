# Router-Side Diagnostic Guide

**Issue:** Port forwarding rule shows as enabled but port 2222 is not accessible externally

---

## Router Diagnostic Steps

### Step 1: Check Router Logs

**Access router admin panel and look for:**

1. **Connection Logs / Firewall Logs:**
   - Look for entries showing blocked connections to port 2222
   - Look for entries showing allowed connections to port 2222
   - Check if there are any errors related to port forwarding

2. **Port Forwarding Logs:**
   - Some routers have a specific log for port forwarding
   - Check for errors or warnings about the Optimus rule

3. **System Logs:**
   - Look for any errors or warnings
   - Check if port forwarding service is running

**What to look for:**
- ❌ "Port forwarding rule failed to apply"
- ❌ "Internal host unreachable"
- ❌ "Port conflict detected"
- ❌ "Firewall blocking port 2222"

---

### Step 2: Verify Router Can Reach Internal Server

**From router admin interface, look for:**

1. **Ping Tool / Network Tools:**
   - Ping 192.168.0.121 from router
   - Should get successful responses

2. **Port Test Tool (if available):**
   - Test if router can connect to 192.168.0.121:22
   - Some routers have built-in port testing

**If router can't reach 192.168.0.121:**
- Check if server is on same network segment
- Check if server firewall is blocking router IP
- Verify server IP hasn't changed

---

### Step 3: Check for Conflicting Rules

**In router admin, check:**

1. **Other Port Forwarding Rules:**
   - Look for any other rules using port 2222
   - Look for any rules using port 22
   - Conflicts can prevent forwarding

2. **DMZ Settings:**
   - If DMZ is enabled, it might conflict with port forwarding
   - DMZ forwards ALL ports to one device

3. **UPnP/NAT-PMP:**
   - Check if UPnP is enabled
   - Sometimes UPnP rules conflict with manual port forwarding

4. **Firewall Rules:**
   - Check if there's a firewall rule blocking port 2222
   - Some routers have separate firewall from port forwarding

---

### Step 4: Test Port Forwarding from Router

**If router has diagnostic tools:**

1. **Port Forwarding Test:**
   - Some routers can test port forwarding rules
   - Look for "Test" or "Diagnose" button next to the rule

2. **External Port Test:**
   - Router might be able to test if external port is accessible
   - Check router's "Port Check" or "External Access" tools

---

### Step 5: Check Router External IP

**Verify router's external IP matches:**

1. **Router Status Page:**
   - Look for "WAN IP" or "External IP"
   - Should show: 114.73.209.140

2. **If IP is different:**
   - Router might have gotten new IP from ISP
   - Port forwarding would still work, but DNS might be wrong
   - Check if IP changed recently

---

### Step 6: Router-Specific Issues

**Common router problems:**

1. **Rule Order:**
   - Some routers process rules in order
   - Try moving Optimus rule to top of list
   - Or delete and recreate it

2. **Rule Format:**
   - Some routers are picky about wildcard "*"
   - Try changing External host from "*" to "0.0.0.0" or leave blank

3. **Protocol Selection:**
   - Make sure it's set to "TCP" not "UDP" or "Both"
   - SSH only uses TCP

4. **Router Firmware Bug:**
   - Some routers have bugs with port forwarding
   - Check router manufacturer's support forums
   - Consider firmware update

---

## Advanced Diagnostics

### Test from Router's Network

**If you can SSH into router or access router shell:**

```bash
# From router (if it has shell access)
# Test if router can reach internal server
ping 192.168.0.121

# Test if router can connect to SSH port
telnet 192.168.0.121 22
# or
nc -zv 192.168.0.121 22
```

### Check Router NAT Table

**Some routers show active NAT connections:**

1. **Look for "NAT Table" or "Active Connections":**
   - Should show connections when you try to connect
   - If nothing appears, port forwarding isn't working
   - If connections appear but timeout, firewall might be blocking

---

## Router Configuration to Try

### Option 1: Delete and Recreate Rule

1. **Delete the Optimus rule**
2. **Click Apply** (save the deletion)
3. **Wait 1 minute**
4. **Recreate the rule:**
   - Service: Optimus
   - External Port: 2222
   - Internal IP: 192.168.0.121
   - Internal Port: 22
   - Protocol: TCP
5. **Click Apply**

### Option 2: Try Different External Port

**If 2222 doesn't work, try a high port:**

1. **Change External Port to:** 22222 (or another high port)
2. **Keep Internal Port as:** 22
3. **Click Apply**
4. **Test:** `ssh -i ~/.ssh/id_optimus -p 22222 chief@114.73.209.140`

### Option 3: Check Router Firewall

**Some routers have separate firewall:**

1. **Look for "Firewall" or "Security" section**
2. **Check if port 2222 is explicitly blocked**
3. **Add exception for port 2222 if needed**

---

## Router Log Locations (Common)

**Where to find logs in router admin:**

- **Netgear:** Advanced → Administration → Logs
- **TP-Link:** Advanced → System Tools → Log
- **Linksys:** Administration → Logs
- **ASUS:** System Log → General Log
- **D-Link:** Tools → System → Logs

**Look for:**
- Port forwarding entries
- Firewall blocks
- NAT translation logs
- Connection attempts

---

## What to Check in Router Logs

**When you try to connect externally, router should log:**

1. **Incoming connection attempt:**
   ```
   [Port Forward] Incoming connection to 114.73.209.140:2222
   ```

2. **NAT translation:**
   ```
   [NAT] Forwarding 114.73.209.140:2222 → 192.168.0.121:22
   ```

3. **If blocked, you'll see:**
   ```
   [Firewall] Blocked connection to port 2222
   ```
   OR
   ```
   [Port Forward] Failed to forward port 2222
   ```

---

## Quick Test: Compare Working vs Non-Working

**Since HTTP/HTTPS work but SSH doesn't:**

1. **Compare the rules:**
   - What's different between Halo HTTP/HTTPS and Optimus?
   - Are they in the same section?
   - Same protocol settings?

2. **Try copying Halo HTTP rule:**
   - Create new rule identical to Halo HTTP
   - Change only the ports (2222 → 22)
   - See if that works

---

## Router Manufacturer Support

**If diagnostics don't reveal the issue:**

1. **Check router support forums:**
   - Search for "port forwarding not working [router model]"
   - Common issue with known fixes

2. **Router firmware update:**
   - Check for firmware updates
   - Some routers have port forwarding bugs fixed in updates

3. **Router reset (last resort):**
   - Factory reset router
   - Reconfigure all port forwarding rules
   - This will fix any corrupted configuration

---

## Alternative: Use Router's Test Feature

**Some routers have built-in port forwarding test:**

1. **Look for "Test" or "Diagnose" button** next to the Optimus rule
2. **Or look for "Port Check" tool** in router admin
3. **Enter:** External IP: 114.73.209.140, Port: 2222
4. **Router will test if port is accessible**

---

## Summary Checklist

When diagnosing from router:

- [ ] Check router logs for port 2222 entries
- [ ] Verify router can ping 192.168.0.121
- [ ] Check for conflicting port forwarding rules
- [ ] Verify router external IP is 114.73.209.140
- [ ] Check router firewall isn't blocking 2222
- [ ] Try deleting and recreating the rule
- [ ] Compare with working HTTP/HTTPS rules
- [ ] Check router firmware version
- [ ] Look for router-specific port forwarding issues

---

## Next Steps

1. **Access router logs** and look for port 2222 entries
2. **Compare Optimus rule with Halo HTTP/HTTPS rules** (what's different?)
3. **Try deleting and recreating the rule**
4. **Check router firewall settings**
5. **Test with different external port** (22222) to rule out ISP blocking

Let me know what you find in the router logs or if you see any differences between the working and non-working rules!


# Alternative Ways to Check Port Forwarding

## Method 1: Online Port Checker Tools

### Option A: YouGetSignal
1. Go to: https://www.yougetsignal.com/tools/open-ports/
2. Enter:
   - **Remote Address:** 114.73.209.140
   - **Port Number:** 2222
3. Click **"Check"**
4. **Result:**
   - ✅ **Open** = Port forwarding working
   - ❌ **Closed/Filtered** = Port forwarding not working

### Option B: CanYouSeeMe
1. Go to: https://canyouseeme.org/
2. Enter port: **2222**
3. Click **"Check Port"**
4. **Result:**
   - ✅ **Success** = Port forwarding working
   - ❌ **Error** = Port forwarding not working

### Option C: PortChecker.co
1. Go to: https://www.portchecker.co/
2. Enter:
   - **IP:** 114.73.209.140
   - **Port:** 2222
3. Click **"Check"**

## Method 2: Monitor Server in Real-Time

### On Optimus Server:

**Run this script to monitor for incoming connections:**
```bash
# Copy check_port_forwarding.sh to server first
sudo tcpdump -i eno1 -n 'tcp port 2222 and tcp[tcpflags] & tcp-syn != 0' -v
```

**Or use the provided script:**
```bash
./check_port_forwarding.sh
```

**What to look for:**
- ✅ **Packets appear** = Port forwarding working
- ❌ **No packets** = Port forwarding not working

### While Monitoring, Test From:
- **Mobile hotspot** (different network)
- **Online port checker** (see Method 1)
- **Friend's network** (external)

## Method 3: Router Admin Panel Check

### Access Router (192.168.0.1):

1. **Check Port Forwarding Status:**
   - Look for **"Active"** or **"Enabled"** status
   - Some routers show **"Last Used"** timestamp
   - Check if rule is **"Applied"** or **"Pending"**

2. **Check Router Logs:**
   - Look for **"Port Forwarding"** or **"NAT"** logs
   - Check for **"Connection"** or **"Firewall"** logs
   - Look for any **"Blocked"** entries

3. **Check Router Firewall:**
   - Ensure **"WAN Access"** is enabled
   - Check **"Port Forwarding"** is enabled globally
   - Verify no **"Block External"** rules

## Method 4: Test Different Ports

### Test Port 80 (HTTP):
```bash
# From external network:
curl -v http://114.73.209.140

# If this works, router forwarding works (just not for SSH)
```

### Test Port 443 (HTTPS):
```bash
# From external network:
curl -v https://114.73.209.140

# If this works, router forwarding works
```

**Note:** If ports 80/443 work but 2222 doesn't, it's a port-specific issue.

## Method 5: Router API/CLI (If Available)

### Some routers support:
- **SSH access** to router
- **API endpoints** for status
- **CLI commands** via telnet

**Check router documentation for:**
- Port forwarding status API
- NAT table commands
- Connection log access

## Method 6: ISP/Network Check

### Check if ISP Blocks Ports:
1. **Contact ISP** - Ask if port 2222 is blocked
2. **Test from different ISP** - Use mobile hotspot
3. **Check CGNAT** - Some ISPs use carrier-grade NAT

### CGNAT Detection:
```bash
# On Optimus:
curl -s ifconfig.me
# Compare with router's WAN IP
# If different, you're behind CGNAT
```

**If behind CGNAT:**
- Port forwarding won't work
- Need VPN solution (Tailscale, WireGuard)

## Method 7: Traceroute Analysis

### From External Network:
```bash
traceroute 114.73.209.140
```

**What to look for:**
- **Hops stop before router** = ISP blocking
- **Hops reach router** = Router issue
- **Timeout at router** = Port forwarding not active

## Method 8: Router Restart Verification

### After Router Restart:

1. **Wait 2-3 minutes** for full boot
2. **Check router admin** - Verify port forwarding still enabled
3. **Test immediately** - Some routers need time to apply rules
4. **Check router logs** - Look for port forwarding activation

## Quick Verification Checklist

- [ ] Online port checker shows port **open**
- [ ] Server tcpdump shows **incoming packets**
- [ ] Router admin shows rule **active/applied**
- [ ] Router firewall allows **external connections**
- [ ] Test from **different network** (not local)
- [ ] Router **restarted** after saving rule
- [ ] ISP **not blocking** port 2222
- [ ] Not behind **CGNAT**

## Recommended Test Sequence

1. **Before router restart:**
   - Use online port checker (Method 1)
   - Monitor server with tcpdump (Method 2)

2. **Save/apply router rule:**
   - Verify in router admin (Method 3)

3. **Restart router:**
   - Wait 2-3 minutes

4. **After router restart:**
   - Test with online port checker
   - Monitor server with tcpdump
   - Test SSH connection

5. **If still fails:**
   - Check ISP blocking (Method 6)
   - Try different port (Method 4)
   - Consider VPN solution

## Most Reliable Method

**Combination of:**
1. **Online port checker** (immediate result)
2. **Server tcpdump** (confirms packets reaching server)
3. **Router admin check** (verifies rule status)

This gives you three independent confirmations!


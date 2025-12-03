# NetComm Router Logs Guide

**Router Model:** NetComm FAST5366LTE-A  
**GUI Version:** 5.53.2  
**Serial:** N7212986D007773

---

## Finding Logs in NetComm Router

### Method 1: System Logs

**Path to try:**
1. **Status** → **System Log**
2. Or: **Administration** → **System Log**
3. Or: **Advanced** → **System Log**
4. Or: **Tools** → **System Log**
5. Or: **Maintenance** → **System Log**

**Look for:**
- "System Log" menu item
- "Event Log" menu item
- "Logs" menu item

### Method 2: Firewall Logs

**Path to try:**
1. **Security** → **Firewall Log**
2. Or: **Firewall** → **Log**
3. Or: **Advanced** → **Firewall** → **Log**

### Method 3: NAT/Port Forwarding Logs

**Path to try:**
1. **Advanced** → **NAT** → **Log**
2. Or: **NAT** → **Port Forwarding** → **Log**
3. Or: **Port Forwarding** → **Log**

---

## Alternative: Check Active Connections

**Since logs might be hard to find, try this instead:**

### Method 1: NAT Table / Active Connections

**Path to try:**
1. **Status** → **NAT Table**
2. Or: **Status** → **Active Connections**
3. Or: **Advanced** → **NAT** → **Active Connections**
4. Or: **Tools** → **Connection Status**

**What to do:**
1. Open this page
2. From external network, try: `nc -zv 114.73.209.140 22222`
3. Watch the table - should see a connection appear
4. If nothing appears, port forwarding isn't working

### Method 2: Port Forwarding Status

**Path to try:**
1. **Advanced** → **NAT** → **Port Forwarding**
2. Or: **Port Forwarding** → **Status**
3. Look for "Active" or "Status" column next to Optimus rule

**What to check:**
- Is the rule showing as "Active"?
- Is there a "Test" button next to the rule?
- Does it show connection count or statistics?

---

## NetComm Router Interface Navigation

**Common menu structure for NetComm routers:**

### Main Menu Items to Check:

1. **Status**
   - System Information
   - NAT Table
   - Active Connections
   - System Log

2. **Advanced**
   - NAT
   - Port Forwarding
   - Firewall
   - System Log

3. **Security**
   - Firewall
   - Firewall Log
   - Port Forwarding

4. **Tools**
   - System Log
   - Diagnostics
   - Connection Status

5. **Maintenance**
   - System Log
   - Event Log

---

## What to Look For

### In System Log:
- Look for entries with "22222" or "2222"
- Look for "Port Forward" entries
- Look for "NAT" entries
- Look for "Firewall" entries
- Look for errors or warnings

### In NAT Table / Active Connections:
- When you try to connect, should see entry like:
  - External: 114.73.209.140:22222
  - Internal: 192.168.0.121:22
  - Status: Established
- If nothing appears, forwarding isn't working

---

## If You Still Can't Find Logs

**Try these diagnostic methods:**

### Method 1: Router Diagnostics Tool

**Look for:**
- **Tools** → **Diagnostics**
- **Advanced** → **Diagnostics**
- **Tools** → **Ping Test**
- **Tools** → **Port Test**

**Test if router can reach Optimus:**
- Ping: 192.168.0.121
- Port Test: 192.168.0.121:22

### Method 2: Check Port Forwarding Rule Details

**In the Port Forwarding section:**
1. Click on the Optimus rule (or edit button)
2. Look for:
   - "Status" or "Active" indicator
   - "Test" button
   - Connection statistics
   - Error messages

### Method 3: Router Support Documentation

**NetComm routers often have:**
- Help button (?) in interface
- Online documentation
- Support portal

**Search for:**
- "How to view logs NetComm router"
- "Port forwarding not working NetComm"
- Your router model + "logs"

---

## Quick Test: Enable Verbose Logging

**Some NetComm routers have logging settings:**

1. **Look for "Log Settings" or "Logging Configuration"**
2. **Enable:**
   - Port Forwarding Logging
   - NAT Logging
   - Firewall Logging
   - Set log level to "Detailed" or "Verbose"

3. **Then try connecting and check logs again**

---

## Alternative Diagnostic: Router Command Line

**If router has CLI/SSH access:**

1. **Look for "CLI" or "Command Line" option**
2. **Or access router via SSH/Telnet** (if enabled)
3. **Run commands:**
   ```bash
   # Check NAT table
   iptables -t nat -L -n -v
   
   # Check port forwarding rules
   cat /proc/net/ip_conntrack | grep 22222
   
   # Check firewall rules
   iptables -L -n -v
   ```

**Note:** Most consumer routers don't expose CLI, but some NetComm routers do

---

## What to Report Back

**After checking, tell me:**

1. **Did you find any log section?** (Yes/No, and which one)
2. **Did you find NAT Table or Active Connections?** (Yes/No)
3. **When you try to connect, do you see any new entries?** (Yes/No)
4. **What does the Optimus port forwarding rule show?** (Active, Enabled, any status?)
5. **Is there a "Test" button next to the rule?** (Yes/No)

---

## Next Steps If Logs Aren't Available

**If you can't find logs, we can:**

1. **Test from router's diagnostic tools** (if available)
2. **Check router firmware update** (might add logging features)
3. **Contact NetComm support** (they can help with router-specific issues)
4. **Try alternative diagnostic methods** (checking from server side)
5. **Use router's port forwarding test feature** (if it exists)

---

## NetComm Router Specific Notes

**NetComm routers (especially ISP-provided ones) often:**
- Have simplified interfaces
- Hide advanced logging features
- May require firmware update for full features
- Sometimes have different interface than consumer routers

**If this is an ISP-provided router:**
- ISP might have locked down some features
- May need to contact ISP for port forwarding support
- ISP might need to enable port forwarding on their end


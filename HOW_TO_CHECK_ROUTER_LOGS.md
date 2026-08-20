# How to Check Router Logs

**Purpose:** Find out why port forwarding for SSH isn't working despite being enabled

---

## Step 1: Access Router Admin Panel

1. **Open web browser**
2. **Navigate to:** `http://192.168.0.1` (or `http://192.168.1.1`)
3. **Log in** with admin credentials

---

## Step 2: Find Logs Section

**Location varies by router brand. Look for one of these menu items:**

### Common Menu Names:
- **Logs**
- **System Log**
- **Event Log**
- **Connection Log**
- **Firewall Log**
- **Security Log**
- **Administration → Logs**
- **Advanced → Logs**

---

## Router-Specific Instructions

### **Netgear Routers**

**Path:**
1. **Advanced** → **Administration** → **Logs**
2. Or: **Advanced** → **Security** → **Event Log**

**What to look for:**
- "Port Forward" entries
- "NAT" entries
- "Firewall" entries
- Look for port 22222 or 2222

**How to test:**
1. Open logs page
2. Try connecting: `ssh -p 22222 chief@114.73.209.140` (from external network)
3. Watch logs in real-time for new entries

---

### **TP-Link Routers**

**Path:**
1. **Advanced** → **System Tools** → **Log**
2. Or: **Advanced** → **Security** → **Firewall** → **Log**

**What to look for:**
- "Port Forwarding" entries
- "NAT" entries
- "Firewall Rule" entries
- Filter by port 22222

**Features:**
- Some TP-Link routers have "Real-time Log" option
- Can filter by type (Firewall, Port Forward, etc.)

---

### **Linksys Routers**

**Path:**
1. **Administration** → **Logs**
2. Or: **Connectivity** → **Firewall** → **Logs**

**What to look for:**
- "Port Forward" entries
- "NAT Translation" entries
- "Blocked Connection" entries

---

### **ASUS Routers**

**Path:**
1. **System Log** → **General Log**
2. Or: **Firewall** → **General Log**

**What to look for:**
- "Port Forward" entries
- "NAT" entries
- Can filter by keyword (search for "22222")

**Features:**
- ASUS routers often have detailed logging
- Can export logs to file
- Real-time log viewing

---

### **D-Link Routers**

**Path:**
1. **Tools** → **System** → **Logs**
2. Or: **Advanced** → **Logs**

**What to look for:**
- "Port Forward" entries
- "NAT" entries
- "Firewall" entries

---

## What to Look For in Logs

### Good Signs (Port Forwarding Working):

```
[Port Forward] Incoming connection to 114.73.209.140:22222
[NAT] Forwarding 114.73.209.140:22222 → 192.168.0.121:22
[Port Forward] Connection established to 192.168.0.121:22
```

### Bad Signs (Port Forwarding Not Working):

```
[Firewall] Blocked connection to port 22222
[Port Forward] Rule not found for port 22222
[Port Forward] Failed to forward port 22222
[NAT] No rule matching port 22222
[Port Forward] Internal host unreachable: 192.168.0.121
```

### No Entries at All:

**If you see NO entries when trying to connect:**
- Router isn't seeing the connection attempts
- Port forwarding isn't even trying
- Could mean:
  - Rule isn't actually active
  - Router firewall is blocking before port forwarding
  - ISP is blocking the port before it reaches router

---

## How to Test and Watch Logs

### Method 1: Real-Time Log Viewing

1. **Open router logs page**
2. **Look for "Refresh" or "Auto-refresh" button** (enable it)
3. **From external network** (mobile hotspot), try:
   ```bash
   ssh -p 22222 chief@114.73.209.140
   ```
4. **Watch logs** - you should see entries appear

### Method 2: Export and Search

1. **Export logs** (if router supports it)
2. **Search for:**
   - "22222"
   - "2222"
   - "port forward"
   - "NAT"
   - "Optimus"

### Method 3: Clear and Test

1. **Clear logs** (if option available)
2. **Try connecting** from external network
3. **Check logs immediately** - should see new entries

---

## Specific Things to Check

### 1. Port Forwarding Logs

**Look for entries like:**
- Port forwarding rule applied
- Port forwarding rule active
- Port forwarding connection attempt
- Port forwarding success/failure

### 2. Firewall Logs

**Look for entries like:**
- Firewall blocked port 22222
- Firewall allowed port 22222
- Firewall rule matched

### 3. NAT Logs

**Look for entries like:**
- NAT translation: 22222 → 22
- NAT connection established
- NAT connection failed

### 4. System/Error Logs

**Look for entries like:**
- Port forwarding service error
- NAT service error
- Configuration error

---

## Router Log Settings

**Some routers let you configure logging:**

1. **Enable Port Forwarding Logging** (if option exists)
2. **Enable Firewall Logging** (if option exists)
3. **Set Log Level** to "Detailed" or "Verbose"
4. **Enable Real-Time Logging** (if available)

---

## Alternative: Router Diagnostic Tools

**Some routers have built-in diagnostics:**

1. **Look for "Diagnostics" or "Tools" section**
2. **Port Forwarding Test:**
   - Some routers can test port forwarding rules
   - Enter: External IP, Port 22222
   - Router will test if rule is working

3. **Connection Test:**
   - Test if router can reach 192.168.0.121:22
   - Some routers have this built-in

---

## If You Can't Find Logs

**Some routers don't have detailed logs. Try:**

1. **Router Status Page:**
   - Look for "Active Connections" or "NAT Table"
   - Should show active port forwarding connections
   - If nothing appears when you try to connect, forwarding isn't working

2. **Router Support:**
   - Check router manual (PDF usually on manufacturer website)
   - Search for "logs" or "port forwarding logs"
   - Contact router manufacturer support

3. **Router Firmware:**
   - Check if firmware update adds logging features
   - Some routers have better logging in newer firmware

---

## Quick Test Procedure

**To see if router is logging at all:**

1. **Open router logs page**
2. **Clear logs** (if possible)
3. **From external network**, try connecting:
   ```bash
   nc -zv 114.73.209.140 22222
   ```
4. **Immediately check logs** - should see something

**If you see entries:**
- ✅ Router is logging
- Look for what it says about port 22222

**If you see nothing:**
- ❌ Router might not be logging port forwarding
- Or connection isn't reaching router
- Try checking "Active Connections" instead

---

## What to Report Back

**After checking logs, tell me:**

1. **Did you find logs?** (Yes/No)
2. **What entries did you see?** (Copy/paste any relevant entries)
3. **When you tried to connect, did new entries appear?** (Yes/No)
4. **What do the entries say?** (Blocked, Allowed, Error, etc.)
5. **Any errors or warnings?** (Copy/paste)

---

## Router Model Specific Help

**If you know your router model, I can give more specific instructions:**

Common models:
- Netgear: Nighthawk, Orbi, etc.
- TP-Link: Archer series
- Linksys: Velop, WRT series
- ASUS: RT-AC, RT-AX series
- D-Link: DIR series

**Tell me your router model and I'll give exact steps!**


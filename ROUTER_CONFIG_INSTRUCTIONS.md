# Router Configuration Instructions for External SSH Access

## What You Need to Do

Configure **port forwarding** on your router to allow external SSH access to Optimus.

## Router Details

- **Router IP:** 192.168.0.1 (default gateway)
- **Optimus Internal IP:** 192.168.0.121
- **SSH Port:** 22 (or 2222 if you prefer)

## Step-by-Step Instructions

### 1. Access Router Admin Panel

1. Open a web browser
2. Navigate to: `http://192.168.0.1` (or `https://192.168.0.1`)
3. Log in with your router admin credentials
   - If you don't know them, check the router label or documentation
   - Common defaults: `admin/admin` or `admin/password`

### 2. Find Port Forwarding Section

Look for one of these sections (varies by router brand):
- **Port Forwarding**
- **Virtual Server**
- **NAT Forwarding**
- **Firewall Rules**
- **Applications & Gaming**

### 3. Add Port Forwarding Rule

Create a new rule with these settings:

**Option A: Use Port 22 (Standard SSH)**
- **Service Name:** SSH-Optimus (or any descriptive name)
- **External Port:** 22
- **Internal IP:** 192.168.0.121
- **Internal Port:** 22
- **Protocol:** TCP
- **Status:** Enabled

**Option B: Use Port 2222 (Alternative, more secure)**
- **Service Name:** SSH-Optimus-Alt
- **External Port:** 2222
- **Internal IP:** 192.168.0.121
- **Internal Port:** 22
- **Protocol:** TCP
- **Status:** Enabled

### 4. Save and Apply

- Click **Save** or **Apply**
- Router may restart (this is normal)
- Wait 1-2 minutes for router to come back online

### 5. Verify External IP

Confirm your external IP is still `114.73.209.140`:
- Visit: https://whatismyipaddress.com
- Or run: `curl ifconfig.me` from Optimus

## Testing

After configuration, I can test external access:

```bash
ssh -i ~/.ssh/id_optimus -p 22 chief@114.73.209.140 "echo 'External access works!'"
```

## Common Router Brands - Quick Reference

### **Netgear:**
- Advanced → Port Forwarding / Port Triggering

### **TP-Link:**
- Advanced → NAT Forwarding → Virtual Servers

### **Linksys:**
- Connectivity → Port Forwarding

### **ASUS:**
- WAN → Virtual Server / Port Forwarding

### **D-Link:**
- Advanced → Port Forwarding

## Troubleshooting

**If you can't access router:**
- Try `http://192.168.0.1` or `http://192.168.1.1`
- Check router label for default IP
- Ensure you're on the same network

**If port forwarding doesn't work:**
- Ensure Optimus firewall allows port 22 (already done ✅)
- Check router logs for blocked connections
- Try using port 2222 instead of 22 (some ISPs block 22)

**If external IP changed:**
- Some ISPs use dynamic IPs
- You may need to set up Dynamic DNS (DDNS) for consistent access

## Security Note

⚠️ **Important:** Opening SSH to the internet exposes your server. Ensure:
- ✅ SSH key authentication is enabled (already done)
- ✅ Root login is disabled (already done)
- ✅ Strong passwords if password auth is enabled
- ✅ Consider using a non-standard port (2222) instead of 22

## Once Complete

Let me know when you've configured the router, and I'll:
1. Test external SSH access
2. Proceed with implementing the transaction signing fix
3. Verify everything works end-to-end


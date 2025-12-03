# Optimus SSH Port Forwarding - Root Cause Analysis

## 🔍 **CRITICAL FINDING**

**Date/Time:** November 27, 2025 at 11:29:46  
**Event:** Optus ISP remotely changed the ExternalPort of PortMapping #1 via TR-069

```
2025 11 27 11:29:46,Info,SYS,The path (Device/NAT/PortMappings/PortMapping[@uid=1]/ExternalPort) has been changed by (optus)
```

## 📋 **Summary**

The router logs reveal that **Optus (your ISP) remotely modified your port forwarding configuration** on November 27th. This explains why external SSH access stopped working despite the rule appearing correct in the router UI.

## 🔧 **What Happened**

1. **TR-069 Remote Management:** Your NetComm router connects to Optus's TR-069 server (`mojo-acs.optusnet.com.au`) regularly for remote management
2. **Remote Configuration Change:** On Nov 27 at 11:29:46, Optus pushed a configuration change that modified `PortMapping[@uid=1]/ExternalPort`
3. **Port Forwarding Broken:** This change likely:
   - Changed the external port to a different value
   - Removed the port forwarding rule entirely
   - Disabled the rule without removing it

## 📊 **Evidence from Logs**

### TR-069 Connection Pattern
The router connects to Optus's TR-069 server approximately every 2 hours:
- Regular connections to `mojo-acs.optusnet.com.au`
- Connections initiated and closed automatically
- Remote configuration changes can be pushed at any time

### The Critical Entry
```
Line 58: 2025 11 27 11:29:46,Info,SYS,The path (Device/NAT/PortMappings/PortMapping[@uid=1]/ExternalPort) has been changed by (optus)
```

This is the **only NAT/PortMapping change** in the logs from Nov 21-28, and it occurred right around when external SSH access stopped working.

## 🎯 **Why This Matters**

1. **ISP Control:** Optus can remotely modify your router configuration via TR-069
2. **Silent Changes:** These changes happen without user notification
3. **UI Discrepancy:** The router UI may still show the old configuration, but the actual forwarding rule has been changed/removed
4. **Persistent Issue:** Even if you reconfigure the port forwarding, Optus may change it again

## ✅ **Solutions**

### Option 1: Disable TR-069 (Recommended)x
1. Log into router admin panel (192.168.0.1)
2. Navigate to **Administration** → **TR-069** or **Remote Management**
3. **Disable TR-069** to prevent Optus from making remote changes
4. Reconfigure your port forwarding rules
5. **Note:** This may affect some ISP services, but will prevent remote configuration changes

### Option 2: Reconfigure After Each Change
1. Check port forwarding rules regularly
2. Reconfigure when they're changed
3. Not ideal for long-term stability

### Option 3: Use a Different Port Range
1. Use ports in the 30000+ range (less likely to be modified by ISP)
2. Still vulnerable to TR-069 changes, but less likely

### Option 4: Contact Optus
1. Request that they stop modifying your port forwarding rules
2. May or may not be successful depending on their policies

## 🔐 **Immediate Action Required**

1. **Check current port forwarding rules** in router admin
2. **Reconfigure SSH port forwarding** (22222 → 192.168.0.121:22)
3. **Disable TR-069** to prevent future changes
4. **Test external SSH access** after reconfiguration

## 📝 **Additional Notes**

- TR-069 is a standard protocol for ISP remote management
- Many ISPs use it for firmware updates and configuration management
- Disabling it may prevent automatic firmware updates (check with Optus)
- The router UI may cache old configuration, so verify actual rules via CLI if possible

---

**Date Analyzed:** November 28, 2025  
**Log File:** log_debug_28-11-2025.csv  
**Router Model:** NetComm FAST5366LTE-A  
**ISP:** Optus


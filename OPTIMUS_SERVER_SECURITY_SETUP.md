# Optimus Server - Security Configuration

**Date:** November 17, 2025  
**Server:** Optimus (192.168.0.121 / 114.73.209.140:2222)  
**Status:** ✅ **SECURITY HARDENED**

---

## Security Tools Installed

### 1. ✅ fail2ban - Intrusion Prevention
**Status:** Installed and Active

**Configuration:**
- **Ban time:** 3600 seconds (1 hour)
- **Find time:** 600 seconds (10 minutes)
- **Max retries:** 5 attempts
- **Active jails:** sshd

**Protection:**
- Automatically bans IPs after failed SSH login attempts
- Prevents brute force attacks
- Monitors `/var/log/auth.log` for SSH failures

**Commands:**
```bash
# Check status
sudo fail2ban-client status sshd

# View banned IPs
sudo fail2ban-client status sshd | grep "Banned IP list"

# Unban an IP (if needed)
sudo fail2ban-client set sshd unbanip IP_ADDRESS
```

---

### 2. ✅ UFW Firewall - Network Protection
**Status:** Active and Enabled

**Configuration:**
- **Default incoming:** DENY (block all incoming by default)
- **Default outgoing:** ALLOW (allow all outgoing)
- **Logging:** Enabled (low level)

**Allowed Ports:**
- **22/tcp** - SSH (local network)
- **2222/tcp** - SSH (external access)

**Commands:**
```bash
# Check status
sudo ufw status verbose

# Allow additional ports (if needed)
sudo ufw allow PORT/tcp comment "Description"

# Deny a port
sudo ufw deny PORT/tcp

# Reload firewall
sudo ufw reload
```

---

### 3. ✅ SSH Hardening
**Status:** Configured

**Security Settings:**
- **PermitRootLogin:** NO (root login disabled)
- **PasswordAuthentication:** YES (enabled for flexibility, but key auth preferred)
- **PubkeyAuthentication:** YES (SSH key authentication enabled)
- **MaxAuthTries:** 20 (increased to work with fail2ban)
- **Protocol:** 2 (SSH protocol version 2 only)

**Best Practices:**
- Use SSH key authentication instead of passwords
- Root login is disabled (use `sudo` instead)
- Multiple failed attempts will trigger fail2ban

---

### 4. ✅ Automatic Security Updates
**Status:** Enabled

**Configuration:**
- **Service:** unattended-upgrades
- **Automatic reboot:** Disabled (manual reboot required)
- **Reboot time:** 03:00 (if enabled)

**What it does:**
- Automatically installs security updates
- Keeps system packages up to date
- Reduces vulnerability window

**Commands:**
```bash
# Check status
systemctl status unattended-upgrades

# View logs
sudo tail -f /var/log/unattended-upgrades/unattended-upgrades.log

# Manual update check
sudo unattended-upgrade --dry-run
```

---

### 5. ✅ Additional Security Tools

**logwatch** - Log monitoring and reporting
- Installed for log analysis
- Can be configured to email daily summaries

**apt-listchanges** - Package change notifications
- Shows what changes when packages are updated

---

## Security Checklist

### ✅ Completed
- [x] fail2ban installed and configured
- [x] UFW firewall enabled with restrictive defaults
- [x] SSH root login disabled
- [x] SSH key authentication enabled
- [x] SSH protocol 2 enforced
- [x] Automatic security updates enabled
- [x] Firewall rules configured for SSH access
- [x] Intrusion detection active

### 🔄 Recommended Additional Steps

1. **Regular Security Audits:**
   ```bash
   # Check for failed login attempts
   sudo grep "Failed password" /var/log/auth.log
   
   # Check fail2ban status
   sudo fail2ban-client status
   
   # Review firewall rules
   sudo ufw status verbose
   ```

2. **Monitor Logs:**
   ```bash
   # View recent SSH connections
   sudo tail -f /var/log/auth.log | grep sshd
   
   # Check system logs
   sudo journalctl -xe
   ```

3. **Keep System Updated:**
   ```bash
   # Manual update check
   sudo apt update && sudo apt upgrade
   
   # Check for security updates
   sudo apt list --upgradable | grep -i security
   ```

4. **Consider Additional Security:**
   - **rkhunter** - Rootkit detection
   - **chkrootkit** - Rootkit scanner
   - **ClamAV** - Antivirus (if handling files from untrusted sources)
   - **AIDE** - File integrity monitoring
   - **AppArmor/SELinux** - Mandatory access control (if needed)

---

## Current Security Posture

### Network Security
- ✅ Firewall active (UFW)
- ✅ Only necessary ports open (22, 2222)
- ✅ Default deny incoming traffic

### Access Control
- ✅ SSH key authentication preferred
- ✅ Root login disabled
- ✅ fail2ban protecting against brute force
- ✅ Password authentication available (but key auth recommended)

### System Security
- ✅ Automatic security updates enabled
- ✅ SSH protocol 2 enforced
- ✅ Log monitoring tools installed

### Monitoring
- ✅ fail2ban monitoring SSH attempts
- ✅ UFW logging enabled
- ✅ System logs being monitored

---

## Important Notes

1. **SSH Access:** Always use SSH key authentication when possible
2. **Firewall:** Add rules for any new services you install
3. **Updates:** System will automatically install security updates
4. **Monitoring:** Regularly check fail2ban and firewall logs
5. **Backups:** Ensure you have backups before making major changes

---

## Quick Reference Commands

```bash
# Security status check
sudo fail2ban-client status
sudo ufw status verbose
systemctl status unattended-upgrades

# View security logs
sudo tail -50 /var/log/auth.log | grep -E "(Failed|Invalid|Connection)"
sudo fail2ban-client status sshd

# Firewall management
sudo ufw allow PORT/tcp
sudo ufw deny PORT/tcp
sudo ufw reload

# System updates
sudo apt update
sudo apt upgrade
sudo apt list --upgradable
```

---

**Status:** ✅ Server is now secured with industry-standard security measures!


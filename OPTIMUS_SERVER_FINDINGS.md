# Optimus Server Access - Findings and Recommendations

**Date:** $(date)  
**Server:** Optimus (192.168.0.121 / 114.73.209.140:2222)  
**User:** chief

## Current Status

### ✅ What's Working
1. **Port Forwarding:** Configured correctly (External 2222 → Internal 22)
2. **Public IP:** Server is reachable at 114.73.209.140
3. **Initial Connection:** Successfully connected initially and verified:
   - Hostname: Optimus
   - User: chief
   - SSH service is running

### ❌ Current Issues
1. **Connection Refused:** After initial successful connection, subsequent attempts are being refused
2. **Rate Limiting:** Likely cause - SSH rate limiting (fail2ban or sshd MaxAuthTries) blocking after multiple connection attempts
3. **Password-Only Auth:** Currently using password authentication (less secure)

## Recommendations (In Order)

### 1. ✅ Set Up SSH Key Authentication
**Status:** Script created, needs to be run on server

**Action Required:**
- Run `setup_optimus_server.sh` on the server to add SSH public key
- This will enable passwordless access and reduce rate limiting issues

**Public Key to Add:**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDhTg1mEv7JqW4mvnRHDhlZWWr0HuQFBXBAj94yu9Jvw
```

**Manual Steps (if script can't be run):**
```bash
# On the server:
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDhTg1mEv7JqW4mvnRHDhlZWWr0HuQFBXBAj94yu9Jvw" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 2. ⏳ Check and Adjust SSH Rate Limiting
**Status:** Needs server-side investigation

**Issues to Check:**
- **fail2ban:** May be blocking IP after failed attempts
- **sshd MaxAuthTries:** Default is 6, may need to increase
- **MaxStartups:** Limits concurrent connections

**Recommended SSH Config Changes** (`/etc/ssh/sshd_config`):
```
MaxAuthTries 10          # Increase from default 6
MaxStartups 20:50:100    # Allow more concurrent connections
LoginGraceTime 120       # Increase timeout
```

**If fail2ban is blocking:**
```bash
# Check status
sudo fail2ban-client status sshd

# Unban IP if needed
sudo fail2ban-client set sshd unbanip YOUR_IP_ADDRESS
```

**After changes:**
```bash
sudo systemctl restart sshd
# or
sudo service ssh restart
```

### 3. ⏳ Review Firewall Rules
**Status:** Needs server-side investigation

**Check:**
- UFW firewall status and rules
- iptables rules
- Router/firewall port forwarding (already configured for 2222→22)

**Commands to run on server:**
```bash
# Check UFW
sudo ufw status verbose

# Ensure SSH ports are allowed
sudo ufw allow 22/tcp
sudo ufw allow 2222/tcp

# Check iptables (if used)
sudo iptables -L -n | grep -E "(2222|22)"
```

### 4. ⏳ Identify Services/Apps That Need Access
**Status:** Pending - need to identify what services should be accessible

**Questions:**
- What services/applications are running on the server?
- What ports do they need to be accessible on?
- Do they need external access or just local network?

**Common services to check:**
- Web servers (port 80, 443)
- API servers (various ports)
- Database servers (usually internal only)
- Other application-specific ports

## Next Steps

1. **Immediate:** Wait for rate limiting to clear (usually 10-30 minutes) or unban IP on server
2. **Short-term:** Run `setup_optimus_server.sh` on server to configure SSH keys
3. **Short-term:** Review and adjust SSH configuration for better connection handling
4. **Short-term:** Review firewall rules
5. **Medium-term:** Identify and configure access for required services

## Connection Commands

### With Password (current):
```bash
sshpass -p '15124353asS$' ssh -o StrictHostKeyChecking=no -p 2222 chief@114.73.209.140
```

### With SSH Key (after setup):
```bash
ssh -p 2222 chief@114.73.209.140
```

## Files Created

1. **setup_optimus_server.sh** - Server-side setup script
2. **OPTIMUS_SERVER_FINDINGS.md** - This document

## Notes

- The server was initially accessible, confirming network and port forwarding are correct
- Current connection issues are likely due to rate limiting from multiple connection attempts
- Once rate limiting clears and SSH keys are set up, access should be stable


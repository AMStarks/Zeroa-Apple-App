# Commands to Run on Optimus Server (192.168.0.121)

Run these commands directly on the server to fix SSH access issues.

## Quick Fix - Run All At Once

```bash
# 1. Add SSH public key for passwordless access
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDhTg1mEv7JqW4mvnRHDhlZWWr0HuQFBXBAj94yu9Jvw" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# 2. Check if fail2ban is blocking connections
sudo fail2ban-client status sshd 2>/dev/null && echo "--- Banned IPs ---" && sudo fail2ban-client status sshd | grep "Banned IP list" || echo "fail2ban not active or not installed"

# 3. Unban all IPs (if fail2ban is active)
sudo fail2ban-client set sshd unbanip 0.0.0.0/0 2>/dev/null || echo "No fail2ban or already unbanned"

# 4. Check and adjust SSH configuration
sudo sed -i 's/^#MaxAuthTries.*/MaxAuthTries 10/' /etc/ssh/sshd_config
sudo sed -i 's/^MaxAuthTries.*/MaxAuthTries 10/' /etc/ssh/sshd_config
grep -q "^MaxAuthTries" /etc/ssh/sshd_config || echo "MaxAuthTries 10" | sudo tee -a /etc/ssh/sshd_config

# 5. Restart SSH service
sudo systemctl restart sshd 2>/dev/null || sudo service ssh restart 2>/dev/null || sudo systemctl restart ssh

echo "=== Fixes Applied ==="
echo "SSH key added, rate limiting adjusted, SSH restarted"
```

## Step-by-Step Fixes

### Step 1: Add SSH Public Key (Enable Passwordless Access)

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDhTg1mEv7JqW4mvnRHDhlZWWr0HuQFBXBAj94yu9Jvw" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
echo "✓ SSH key added"
```

### Step 2: Check and Fix fail2ban (Rate Limiting)

```bash
# Check if fail2ban is installed and active
if command -v fail2ban-client &> /dev/null; then
    echo "fail2ban is installed"
    sudo fail2ban-client status sshd
    
    # Show banned IPs
    echo "--- Checking for banned IPs ---"
    sudo fail2ban-client status sshd | grep "Banned IP list"
    
    # Unban all IPs (you can specify a specific IP instead)
    echo "Unbanning all IPs..."
    sudo fail2ban-client set sshd unbanip 0.0.0.0/0
else
    echo "fail2ban is not installed"
fi
```

### Step 3: Adjust SSH Configuration (Increase Connection Limits)

```bash
# Backup the config first
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Increase MaxAuthTries (default is 6)
sudo sed -i 's/^#MaxAuthTries.*/MaxAuthTries 10/' /etc/ssh/sshd_config
sudo sed -i 's/^MaxAuthTries.*/MaxAuthTries 10/' /etc/ssh/sshd_config
# If it doesn't exist, add it
grep -q "^MaxAuthTries" /etc/ssh/sshd_config || echo "MaxAuthTries 10" | sudo tee -a /etc/ssh/sshd_config

# Increase MaxStartups (allows more concurrent connections)
sudo sed -i 's/^#MaxStartups.*/MaxStartups 20:50:100/' /etc/ssh/sshd_config
sudo sed -i 's/^MaxStartups.*/MaxStartups 20:50:100/' /etc/ssh/sshd_config
grep -q "^MaxStartups" /etc/ssh/sshd_config || echo "MaxStartups 20:50:100" | sudo tee -a /etc/ssh/sshd_config

# Increase LoginGraceTime
sudo sed -i 's/^#LoginGraceTime.*/LoginGraceTime 120/' /etc/ssh/sshd_config
sudo sed -i 's/^LoginGraceTime.*/LoginGraceTime 120/' /etc/ssh/sshd_config
grep -q "^LoginGraceTime" /etc/ssh/sshd_config || echo "LoginGraceTime 120" | sudo tee -a /etc/ssh/sshd_config

# Verify changes
echo "=== Current SSH Config ==="
grep -E "^(MaxAuthTries|MaxStartups|LoginGraceTime)" /etc/ssh/sshd_config
```

### Step 4: Restart SSH Service

```bash
# Test the config first
sudo sshd -t

# If test passes, restart SSH
if [ $? -eq 0 ]; then
    sudo systemctl restart sshd 2>/dev/null || sudo service ssh restart 2>/dev/null || sudo systemctl restart ssh
    echo "✓ SSH service restarted"
else
    echo "✗ SSH config has errors, not restarting"
    echo "Restore backup: sudo cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config"
fi
```

### Step 5: Check Firewall Rules

```bash
# Check UFW status
if command -v ufw &> /dev/null; then
    echo "=== UFW Firewall Status ==="
    sudo ufw status verbose
    
    # Ensure SSH ports are allowed
    sudo ufw allow 22/tcp
    sudo ufw allow 2222/tcp
    echo "✓ SSH ports allowed in UFW"
fi

# Check iptables
if command -v iptables &> /dev/null; then
    echo "=== iptables Rules for SSH ==="
    sudo iptables -L -n | grep -E "(2222|22)" || echo "No specific iptables rules for SSH ports"
fi
```

### Step 6: Verify Everything is Working

```bash
echo "=== Verification ==="
echo "1. SSH key file:"
ls -la ~/.ssh/authorized_keys

echo ""
echo "2. SSH service status:"
systemctl status sshd 2>/dev/null | head -5 || service ssh status 2>/dev/null | head -5

echo ""
echo "3. Current SSH connections:"
who

echo ""
echo "4. SSH config values:"
grep -E "^(MaxAuthTries|MaxStartups|LoginGraceTime)" /etc/ssh/sshd_config 2>/dev/null || echo "Using defaults"
```

## One-Liner Quick Fix

If you want to run everything at once, copy and paste this:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDhTg1mEv7JqW4mvnRHDhlZWWr0HuQFBXBAj94yu9Jvw" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && sudo fail2ban-client set sshd unbanip 0.0.0.0/0 2>/dev/null; sudo sed -i 's/^#MaxAuthTries.*/MaxAuthTries 10/; s/^MaxAuthTries [0-9]*/MaxAuthTries 10/' /etc/ssh/sshd_config && grep -q "^MaxAuthTries" /etc/ssh/sshd_config || echo "MaxAuthTries 10" | sudo tee -a /etc/ssh/sshd_config && sudo systemctl restart sshd 2>/dev/null || sudo service ssh restart && echo "✓ All fixes applied!"
```

## After Running These Commands

1. Wait 1-2 minutes for SSH to fully restart
2. Try connecting from your local machine again
3. The connection should work with SSH key authentication (no password needed)

## Troubleshooting

If issues persist:

```bash
# Check SSH logs for errors
sudo tail -50 /var/log/auth.log | grep sshd

# Or on some systems:
sudo journalctl -u sshd -n 50
```


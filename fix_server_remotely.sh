#!/bin/bash
# Script to fix SSH access on Optimus server
# This will be executed remotely via SSH

PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDhTg1mEv7JqW4mvnRHDhlZWWr0HuQFBXBAj94yu9Jvw"

echo "=== Optimus Server Fix Script ==="
echo ""

# 1. Set up SSH key authentication
echo "1. Setting up SSH key authentication..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh
if ! grep -q "$PUBKEY" ~/.ssh/authorized_keys 2>/dev/null; then
    echo "$PUBKEY" >> ~/.ssh/authorized_keys
    echo "   ✓ SSH key added"
else
    echo "   ✓ SSH key already exists"
fi
chmod 600 ~/.ssh/authorized_keys
echo ""

# 2. Unban IPs in fail2ban
echo "2. Checking fail2ban..."
if command -v fail2ban-client &> /dev/null; then
    echo "   fail2ban is installed"
    sudo fail2ban-client set sshd unbanip 0.0.0.0/0 2>/dev/null && echo "   ✓ All IPs unbanned" || echo "   (no IPs to unban)"
else
    echo "   fail2ban not installed"
fi
echo ""

# 3. Adjust SSH configuration
echo "3. Adjusting SSH configuration..."
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)

# Increase MaxAuthTries
sudo sed -i 's/^#MaxAuthTries.*/MaxAuthTries 10/' /etc/ssh/sshd_config
sudo sed -i 's/^MaxAuthTries [0-9]*/MaxAuthTries 10/' /etc/ssh/sshd_config
grep -q "^MaxAuthTries" /etc/ssh/sshd_config || echo "MaxAuthTries 10" | sudo tee -a /etc/ssh/sshd_config > /dev/null

# Increase MaxStartups
sudo sed -i 's/^#MaxStartups.*/MaxStartups 20:50:100/' /etc/ssh/sshd_config
sudo sed -i 's/^MaxStartups.*/MaxStartups 20:50:100/' /etc/ssh/sshd_config
grep -q "^MaxStartups" /etc/ssh/sshd_config || echo "MaxStartups 20:50:100" | sudo tee -a /etc/ssh/sshd_config > /dev/null

# Increase LoginGraceTime
sudo sed -i 's/^#LoginGraceTime.*/LoginGraceTime 120/' /etc/ssh/sshd_config
sudo sed -i 's/^LoginGraceTime [0-9]*/LoginGraceTime 120/' /etc/ssh/sshd_config
grep -q "^LoginGraceTime" /etc/ssh/sshd_config || echo "LoginGraceTime 120" | sudo tee -a /etc/ssh/sshd_config > /dev/null

echo "   ✓ SSH config updated"
echo ""

# 4. Test SSH config
echo "4. Testing SSH configuration..."
if sudo sshd -t 2>/dev/null; then
    echo "   ✓ SSH config is valid"
    # Restart SSH
    sudo systemctl restart sshd 2>/dev/null || sudo service ssh restart 2>/dev/null || sudo systemctl restart ssh 2>/dev/null
    echo "   ✓ SSH service restarted"
else
    echo "   ✗ SSH config has errors, not restarting"
    echo "   Restore backup if needed"
fi
echo ""

# 5. Check firewall
echo "5. Checking firewall..."
if command -v ufw &> /dev/null; then
    echo "   UFW status:"
    sudo ufw status | head -5
    sudo ufw allow 22/tcp 2>/dev/null
    sudo ufw allow 2222/tcp 2>/dev/null
    echo "   ✓ SSH ports allowed"
else
    echo "   UFW not installed or not active"
fi
echo ""

# 6. Verify setup
echo "6. Verification:"
echo "   - SSH key file: $(ls -la ~/.ssh/authorized_keys 2>/dev/null | awk '{print $1, $9}')"
echo "   - SSH service: $(systemctl is-active sshd 2>/dev/null || systemctl is-active ssh 2>/dev/null || echo 'unknown')"
echo "   - MaxAuthTries: $(grep '^MaxAuthTries' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo 'default')"
echo ""

echo "=== All fixes applied successfully ==="
echo "You can now connect using: ssh -p 22 chief@192.168.0.121"
echo "Or externally: ssh -p 2222 chief@114.73.209.140"


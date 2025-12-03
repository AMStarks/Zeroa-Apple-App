#!/bin/bash
# Server setup script for Optimus server
# Run this script ON THE SERVER (192.168.0.121) to improve SSH access

set -e

echo "=== Optimus Server SSH Configuration Script ==="
echo ""

# 1. Add SSH public key for passwordless access
echo "1. Setting up SSH key authentication..."
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDhTg1mEv7JqW4mvnRHDhlZWWr0HuQFBXBAj94yu9Jvw"
SSH_DIR="$HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ ! -f "$AUTH_KEYS" ] || ! grep -q "$PUBKEY" "$AUTH_KEYS" 2>/dev/null; then
    echo "$PUBKEY" >> "$AUTH_KEYS"
    echo "✓ SSH key added"
else
    echo "✓ SSH key already exists"
fi
chmod 600 "$AUTH_KEYS"
echo ""

# 2. Check SSH rate limiting configuration
echo "2. Checking SSH rate limiting (fail2ban)..."
if command -v fail2ban-client &> /dev/null; then
    echo "  fail2ban is installed"
    fail2ban-client status sshd 2>/dev/null || echo "  SSH jail not active"
else
    echo "  fail2ban is not installed"
    echo "  Consider installing: sudo apt install fail2ban"
fi
echo ""

# 3. Check SSH daemon configuration
echo "3. Checking SSH daemon configuration..."
SSHD_CONFIG="/etc/ssh/sshd_config"
if [ -f "$SSHD_CONFIG" ]; then
    echo "  Current SSH settings:"
    echo "  - MaxAuthTries: $(grep -i "^MaxAuthTries" "$SSHD_CONFIG" || echo '  MaxAuthTries: (default: 6)')"
    echo "  - MaxStartups: $(grep -i "^MaxStartups" "$SSHD_CONFIG" || echo '  MaxStartups: (default: 10:30:100)')"
    echo "  - LoginGraceTime: $(grep -i "^LoginGraceTime" "$SSHD_CONFIG" || echo '  LoginGraceTime: (default: 60)')"
    echo "  - PasswordAuthentication: $(grep -i "^PasswordAuthentication" "$SSHD_CONFIG" || echo '  PasswordAuthentication: (default: yes)')"
    echo "  - PubkeyAuthentication: $(grep -i "^PubkeyAuthentication" "$SSHD_CONFIG" || echo '  PubkeyAuthentication: (default: yes)')"
else
    echo "  SSH config file not found at $SSHD_CONFIG"
fi
echo ""

# 4. Check firewall status
echo "4. Checking firewall status..."
if command -v ufw &> /dev/null; then
    echo "  UFW status:"
    sudo ufw status verbose 2>/dev/null || echo "  (requires sudo)"
elif command -v iptables &> /dev/null; then
    echo "  iptables is available"
    sudo iptables -L -n | grep -E "(2222|22)" || echo "  (no specific rules for SSH ports visible)"
else
    echo "  No common firewall tool detected"
fi
echo ""

# 5. Check SSH service status
echo "5. Checking SSH service status..."
if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
    echo "  ✓ SSH service is running"
    systemctl status sshd 2>/dev/null | head -3 || systemctl status ssh 2>/dev/null | head -3
else
    echo "  SSH service status check (may need sudo)"
fi
echo ""

# 6. Check for active connections and rate limits
echo "6. Current SSH connections:"
who
echo ""

# 7. Recommendations
echo "=== RECOMMENDATIONS ==="
echo ""
echo "To improve SSH access, consider:"
echo ""
echo "A. Increase SSH connection limits (edit /etc/ssh/sshd_config):"
echo "   MaxAuthTries 10"
echo "   MaxStartups 20:50:100"
echo "   LoginGraceTime 120"
echo ""
echo "B. If using fail2ban, check jail settings:"
echo "   sudo fail2ban-client status sshd"
echo "   sudo fail2ban-client set sshd unbanip YOUR_IP"
echo ""
echo "C. Check firewall rules:"
echo "   sudo ufw status"
echo "   sudo ufw allow 22/tcp"
echo "   sudo ufw allow 2222/tcp"
echo ""
echo "D. After making changes, restart SSH:"
echo "   sudo systemctl restart sshd"
echo "   # or"
echo "   sudo service ssh restart"
echo ""
echo "=== Script completed ==="


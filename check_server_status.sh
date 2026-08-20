#!/bin/bash
# Run this on the server to show current status

echo "=== Server SSH Status Check ==="
echo ""
echo "1. SSH Key File:"
cat ~/.ssh/authorized_keys 2>/dev/null || echo "File not found or empty"
echo ""
echo "2. File Permissions:"
ls -la ~/.ssh/ 2>/dev/null || echo ".ssh directory not found"
echo ""
echo "3. SSH Config (Authentication):"
sudo grep -E "^(PasswordAuthentication|PubkeyAuthentication|MaxAuthTries)" /etc/ssh/sshd_config 2>/dev/null || echo "Could not read config"
echo ""
echo "4. SSH Service Status:"
systemctl is-active sshd 2>/dev/null || systemctl is-active ssh 2>/dev/null || echo "Service status unknown"
echo ""
echo "5. Recent Auth Logs:"
sudo tail -5 /var/log/auth.log 2>/dev/null | grep sshd || echo "Could not read logs"
echo ""
echo "=== End of Status ==="


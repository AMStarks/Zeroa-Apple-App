#!/bin/bash
# Script to check server connectivity and diagnose port forwarding

echo "=== Server Connection Diagnostics ==="
echo ""

# Test 1: Port connectivity
echo "1. Testing port 2222 connectivity..."
if nc -zv -G 5 114.73.209.140 2222 2>&1 | grep -q "succeeded"; then
    echo "   ✓ Port 2222 is open"
else
    echo "   ✗ Port 2222 is not reachable"
    echo "   This suggests port forwarding may not be working"
fi
echo ""

# Test 2: Try SSH connection
echo "2. Attempting SSH connection..."
sshpass -p '15124353asS$' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p 2222 chief@114.73.209.140 "echo 'Connection successful'; echo 'Checking recent SSH logs:'; sudo tail -10 /var/log/auth.log | grep sshd | tail -5" 2>&1 | head -20

echo ""
echo "=== Recommendations ==="
echo ""
echo "From the SSH logs you showed, I notice:"
echo "1. SSH is running and listening on port 22 ✓"
echo "2. Failed attempts are from 192.168.0.1 (local network)"
echo "3. No external connection attempts visible in logs"
echo ""
echo "This suggests the port forwarding (2222 → 22) may not be working"
echo "or external connections are being blocked by a firewall."
echo ""
echo "On the server, please run:"
echo "  sudo tail -50 /var/log/auth.log | grep -E '(114.73|2222|external)'"
echo ""
echo "This will show if any external connection attempts are reaching the server."


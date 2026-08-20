#!/bin/bash
# Test script for Optimus server connectivity
# Run this locally to test connection status

SERVER="114.73.209.140"
PORT="2222"
USER="chief"
PASSWORD="15124353asS$"

echo "=== Optimus Server Connection Test ==="
echo "Server: $SERVER:$PORT"
echo "User: $USER"
echo ""

# Test 1: Port connectivity
echo "1. Testing port connectivity..."
if nc -zv -G 5 "$SERVER" "$PORT" 2>&1 | grep -q "succeeded"; then
    echo "   ✓ Port $PORT is open and reachable"
    PORT_OK=true
else
    echo "   ✗ Port $PORT is not reachable (connection refused or timeout)"
    PORT_OK=false
fi
echo ""

# Test 2: SSH connection
if [ "$PORT_OK" = true ]; then
    echo "2. Testing SSH connection..."
    if sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -p "$PORT" "$USER@$SERVER" "echo 'Connection successful'" 2>/dev/null; then
        echo "   ✓ SSH connection successful"
        SSH_OK=true
    else
        echo "   ✗ SSH connection failed (may be rate limited)"
        SSH_OK=false
    fi
    echo ""
fi

# Test 3: SSH key authentication (if key exists)
if [ -f ~/.ssh/id_ed25519 ] || [ -f ~/.ssh/id_rsa ]; then
    echo "3. Testing SSH key authentication..."
    KEY_FILE=""
    if [ -f ~/.ssh/id_ed25519 ]; then
        KEY_FILE=~/.ssh/id_ed25519
    elif [ -f ~/.ssh/id_rsa ]; then
        KEY_FILE=~/.ssh/id_rsa
    fi
    
    if [ -n "$KEY_FILE" ] && ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -i "$KEY_FILE" -p "$PORT" "$USER@$SERVER" "echo 'Key auth successful'" 2>/dev/null; then
        echo "   ✓ SSH key authentication working"
        KEY_OK=true
    else
        echo "   ✗ SSH key authentication not configured or not working"
        KEY_OK=false
    fi
    echo ""
fi

# Summary
echo "=== Summary ==="
if [ "$PORT_OK" = true ] && [ "$SSH_OK" = true ]; then
    echo "✓ Server is accessible"
    exit 0
elif [ "$PORT_OK" = true ] && [ "$SSH_OK" = false ]; then
    echo "⚠ Port is open but SSH connection is failing (likely rate limited)"
    echo "  Recommendation: Wait 10-30 minutes or unban IP on server"
    exit 1
elif [ "$PORT_OK" = false ]; then
    echo "✗ Server is not reachable"
    echo "  Recommendation: Check server status, firewall, and port forwarding"
    exit 2
fi


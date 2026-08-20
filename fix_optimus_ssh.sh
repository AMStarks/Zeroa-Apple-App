#!/bin/bash
# Fix Optimus SSH External Access
# This script helps diagnose and verify SSH port forwarding

set -e

echo "═══════════════════════════════════════════════════════════"
echo "🔧 Optimus SSH External Access Fix Script"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
OPTIMUS_EXTERNAL_IP="114.73.209.140"
OPTIMUS_INTERNAL_IP="192.168.0.121"
SSH_PORT="2222"
SSH_KEY="$HOME/.ssh/id_optimus"
SSH_USER="chief"

echo "📋 Configuration:"
echo "   External IP: $OPTIMUS_EXTERNAL_IP"
echo "   Internal IP: $OPTIMUS_INTERNAL_IP"
echo "   SSH Port: $SSH_PORT"
echo "   SSH Key: $SSH_KEY"
echo "   SSH User: $SSH_USER"
echo ""

# Step 1: Check SSH key exists
echo "Step 1: Checking SSH key..."
if [ -f "$SSH_KEY" ]; then
    echo -e "${GREEN}✅ SSH key exists: $SSH_KEY${NC}"
    ls -lh "$SSH_KEY"
else
    echo -e "${RED}❌ SSH key not found: $SSH_KEY${NC}"
    exit 1
fi
echo ""

# Step 2: Test local SSH access (if on same network)
echo "Step 2: Testing local SSH access..."
if ping -c 1 -W 2 "$OPTIMUS_INTERNAL_IP" &>/dev/null; then
    echo -e "${GREEN}✅ Server is reachable on local network${NC}"
    echo "   Attempting local SSH connection..."
    if ssh -i "$SSH_KEY" -p 22 -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$OPTIMUS_INTERNAL_IP" "echo 'Local SSH works'" 2>/dev/null; then
        echo -e "${GREEN}✅ Local SSH access working${NC}"
        LOCAL_ACCESS=true
    else
        echo -e "${YELLOW}⚠️  Local SSH access failed (might not be on same network)${NC}"
        LOCAL_ACCESS=false
    fi
else
    echo -e "${YELLOW}⚠️  Not on local network (192.168.0.x)${NC}"
    LOCAL_ACCESS=false
fi
echo ""

# Step 3: Test external port connectivity
echo "Step 3: Testing external port connectivity..."
echo "   Testing port $SSH_PORT on $OPTIMUS_EXTERNAL_IP..."

if command -v nc &> /dev/null; then
    if nc -zv -w 5 "$OPTIMUS_EXTERNAL_IP" "$SSH_PORT" 2>&1 | grep -q "succeeded"; then
        echo -e "${GREEN}✅ Port $SSH_PORT is OPEN and accessible${NC}"
        PORT_OPEN=true
    else
        echo -e "${RED}❌ Port $SSH_PORT is CLOSED or not forwarded${NC}"
        PORT_OPEN=false
    fi
else
    echo -e "${YELLOW}⚠️  'nc' (netcat) not found, skipping port test${NC}"
    PORT_OPEN=false
fi
echo ""

# Step 4: Test external SSH connection
echo "Step 4: Testing external SSH connection..."
if ssh -i "$SSH_KEY" -p "$SSH_PORT" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$OPTIMUS_EXTERNAL_IP" "echo 'External SSH works' && hostname && uptime" 2>/dev/null; then
    echo -e "${GREEN}✅ External SSH access working!${NC}"
    EXTERNAL_SSH=true
else
    echo -e "${RED}❌ External SSH access failed${NC}"
    EXTERNAL_SSH=false
fi
echo ""

# Step 5: Summary and recommendations
echo "═══════════════════════════════════════════════════════════"
echo "📊 Summary"
echo "═══════════════════════════════════════════════════════════"
echo ""

if [ "$EXTERNAL_SSH" = true ]; then
    echo -e "${GREEN}✅ SUCCESS: External SSH access is working!${NC}"
    echo ""
    echo "You can now connect using:"
    echo "  ssh -i $SSH_KEY -p $SSH_PORT $SSH_USER@$OPTIMUS_EXTERNAL_IP"
    exit 0
fi

echo -e "${RED}❌ External SSH access is NOT working${NC}"
echo ""

if [ "$PORT_OPEN" = false ]; then
    echo "🔍 Diagnosis: Port $SSH_PORT is not accessible externally"
    echo ""
    echo "📝 Action Required: Configure router port forwarding"
    echo ""
    echo "Router Configuration Needed:"
    echo "  ┌─────────────────────────────────────────────┐"
    echo "  │ Service Name: SSH-Optimus                    │"
    echo "  │ External Port: $SSH_PORT                                    │"
    echo "  │ Internal IP: $OPTIMUS_INTERNAL_IP                    │"
    echo "  │ Internal Port: 22                            │"
    echo "  │ Protocol: TCP                                │"
    echo "  │ Status: Enabled                              │"
    echo "  └─────────────────────────────────────────────┘"
    echo ""
    echo "Router Access:"
    echo "  1. Open browser: http://192.168.0.1"
    echo "  2. Log in with router admin credentials"
    echo "  3. Find 'Port Forwarding' or 'Virtual Server' section"
    echo "  4. Add the rule above"
    echo "  5. Save and apply"
    echo "  6. Wait 1-2 minutes for router to restart"
    echo "  7. Run this script again to verify"
    echo ""
fi

if [ "$LOCAL_ACCESS" = true ]; then
    echo "💡 Tip: You have local network access"
    echo "   You can use this to check server status:"
    echo "   ssh -i $SSH_KEY -p 22 $SSH_USER@$OPTIMUS_INTERNAL_IP"
    echo ""
fi

echo "📚 See OPTIMUS_EXTERNAL_PORT_ANALYSIS.md for detailed analysis"
echo ""

exit 1


#!/bin/bash
# Test script to check iPhone network connectivity when connected via USB

echo "🔍 iPhone Network Diagnostics"
echo "=============================="
echo ""

# Check if device is connected
if ! command -v ideviceinfo &> /dev/null; then
    echo "⚠️  ideviceinfo not found. Install libimobiledevice:"
    echo "   brew install libimobiledevice"
    echo ""
    echo "Or check manually:"
    echo "1. Open Xcode → Window → Devices and Simulators"
    echo "2. Select your iPhone"
    echo "3. Check 'Network' section for IP address"
    exit 1
fi

# Get device UDID
UDID=$(idevice_id -l | head -n1)
if [ -z "$UDID" ]; then
    echo "❌ No iPhone connected via USB"
    echo ""
    echo "Please:"
    echo "1. Connect iPhone via USB"
    echo "2. Trust this computer on iPhone"
    echo "3. Run this script again"
    exit 1
fi

echo "✅ iPhone connected: $UDID"
echo ""

# Get network info
echo "📱 iPhone Network Information:"
echo "-------------------------------"
ideviceinfo -u "$UDID" | grep -E "WiFiAddress|ModelNumber|ProductType" || echo "Could not retrieve network info"
echo ""

# Check if we can ping the server
echo "🌐 Testing connectivity to server (192.168.0.121):"
echo "---------------------------------------------------"
if ping -c 2 192.168.0.121 &> /dev/null; then
    echo "✅ Server is reachable from this Mac"
else
    echo "❌ Server is NOT reachable from this Mac"
fi
echo ""

# Check local network IP
echo "💻 This Mac's IP address:"
ifconfig | grep -A 5 "inet " | grep -E "inet 192.168" | head -1
echo ""

echo "📋 Manual Check on iPhone:"
echo "1. Settings → Wi-Fi → Tap (i) next to network"
echo "2. Check 'IP Address' - should be 192.168.0.XXX"
echo "3. Open Safari → Navigate to: http://192.168.0.121/api/health"
echo "4. Should see JSON response if network is working"
echo ""

echo "🔍 If iPhone IP is NOT 192.168.0.XXX:"
echo "   → iPhone is on different network"
echo "   → Connect iPhone to same WiFi as server"
echo ""


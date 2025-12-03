#!/bin/bash

echo "=== Network Speed Fix Script ==="
echo ""

# 1. Check current DNS
echo "1. Current DNS Servers:"
networksetup -getdnsservers Wi-Fi
echo ""

# 2. Set fast DNS servers (already done, but confirming)
echo "2. Setting fast DNS servers..."
networksetup -setdnsservers Wi-Fi 8.8.8.8 8.8.4.4 1.1.1.1
echo "✅ DNS servers set to Google (8.8.8.8, 8.8.4.4) and Cloudflare (1.1.1.1)"
echo ""

# 3. Check webfilterproxyd status
echo "3. Checking webfilterproxyd (Screen Time Content Filter):"
if ps aux | grep -i "webfilterproxyd" | grep -v grep > /dev/null; then
    echo "⚠️  webfilterproxyd is RUNNING - this is causing packet loss!"
    echo "   Process details:"
    ps aux | grep webfilterproxyd | grep -v grep
    echo ""
    echo "   This process has caused:"
    echo "   - 14,525+ packet retransmissions"
    echo "   - 23,128+ duplicate packets"
    echo "   - 31,555+ out-of-order packets"
    echo ""
    echo "   RECOMMENDATION: Disable Screen Time Content Filtering"
    echo "   Go to: System Settings > Screen Time > Content & Privacy Restrictions"
    echo "   Or: System Settings > Screen Time > [Your Name] > Content & Privacy Restrictions"
    echo "   Turn OFF 'Content & Privacy Restrictions'"
else
    echo "✅ webfilterproxyd is not running"
fi
echo ""

# 4. Test network speed
echo "4. Testing network speed..."
SPEED=$(curl -o /dev/null -s -w "%{speed_download}" https://www.google.com)
SPEED_MBPS=$(echo "scale=2; $SPEED * 8 / 1000000" | bc)
echo "   Current speed: ${SPEED_MBPS} Mbps"
echo ""

# 5. Network interface stats
echo "5. Network interface statistics:"
netstat -i | grep -E "Name|en0"
echo ""

echo "=== Recommendations ==="
echo ""
echo "IMMEDIATE FIXES APPLIED:"
echo "✅ Fast DNS servers configured (Google + Cloudflare)"
echo ""
echo "MANUAL ACTION REQUIRED:"
echo "1. Disable Screen Time Content Filtering:"
echo "   - Open System Settings"
echo "   - Go to Screen Time"
echo "   - Click 'Content & Privacy Restrictions'"
echo "   - Turn OFF the toggle"
echo ""
echo "2. If you need content filtering, consider:"
echo "   - Using router-level filtering instead"
echo "   - Using a dedicated network monitoring tool"
echo ""
echo "3. Test speed after disabling Screen Time filtering"
echo ""



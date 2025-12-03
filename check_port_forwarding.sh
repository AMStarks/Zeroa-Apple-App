#!/bin/bash
# Port Forwarding Check Script
# Run this on Optimus to monitor for incoming connections

echo "🔍 Port Forwarding Monitor"
echo "=========================="
echo ""
echo "Monitoring port 2222 for incoming connections..."
echo "This will show if router port forwarding is working."
echo ""
echo "To test: From external network, run:"
echo "  nc -zv 114.73.209.140 2222"
echo ""
echo "Or use online tool:"
echo "  https://www.yougetsignal.com/tools/open-ports/"
echo ""
echo "Press Ctrl+C to stop monitoring"
echo ""

# Monitor for SYN packets (connection attempts)
sudo tcpdump -i eno1 -n 'tcp port 2222 and tcp[tcpflags] & tcp-syn != 0' -v 2>&1


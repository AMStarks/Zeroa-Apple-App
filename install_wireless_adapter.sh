#!/bin/bash
# Script to install RTL88x2bu wireless adapter driver
# Run this on the Optimus server with sudo access

echo "=== Installing RTL88x2bu Wireless Adapter Driver ==="
echo ""

# 1. Update system and install dependencies
echo "1. Installing dependencies..."
sudo apt update
sudo apt install -y dkms build-essential git linux-headers-$(uname -r) wireless-tools iw wpasupplicant

# 2. Clone the RTL88x2bu driver repository
echo ""
echo "2. Downloading RTL88x2bu driver..."
cd /tmp
if [ -d "rtl88x2bu" ]; then
    echo "   Driver directory exists, updating..."
    cd rtl88x2bu
    git pull
else
    git clone https://github.com/morrownr/88x2bu-20210702.git rtl88x2bu
    cd rtl88x2bu
fi

# 3. Install the driver using dkms
echo ""
echo "3. Installing driver with dkms..."
sudo ./install-driver.sh

# 4. Check if driver is loaded
echo ""
echo "4. Checking driver status..."
sleep 2
lsmod | grep 88x2bu || echo "   Driver may need a reboot to load"

# 5. Check wireless interface
echo ""
echo "5. Checking wireless interface..."
ip link show | grep -i wl

# 6. Enable wireless interface
echo ""
echo "6. Enabling wireless interface..."
WIFI_INTERFACE=$(ip link show | grep -oP 'wlx\w+' | head -1)
if [ -n "$WIFI_INTERFACE" ]; then
    echo "   Found interface: $WIFI_INTERFACE"
    sudo ip link set $WIFI_INTERFACE up
    echo "   Interface enabled"
else
    echo "   No wireless interface found"
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "If the driver didn't load, you may need to:"
echo "1. Reboot the system: sudo reboot"
echo "2. Or manually load: sudo modprobe 88x2bu"
echo ""
echo "To connect to WiFi, use:"
echo "  sudo nmtui  (text-based network manager)"
echo "  or"
echo "  sudo iwconfig $WIFI_INTERFACE essid 'NETWORK_NAME' key 'PASSWORD'"
echo "  sudo dhclient $WIFI_INTERFACE"


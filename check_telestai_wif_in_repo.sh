#!/bin/bash

# Script to check Telestai GitHub repository for WIF version byte
# This can be run locally or we can check the source code directly

echo "🔍 Checking Telestai Repository for WIF Version Byte"
echo "===================================================="
echo ""

# If you have the repo cloned locally:
if [ -d "../telestai" ] || [ -d "telestai" ]; then
    REPO_DIR="../telestai"
    if [ ! -d "$REPO_DIR" ]; then
        REPO_DIR="telestai"
    fi
    
    echo "✅ Found local Telestai repository: $REPO_DIR"
    echo ""
    
    echo "1️⃣ Searching for WIF/PRIVKEY version byte definitions..."
    echo ""
    grep -r "PRIVKEY_ADDRESS\|WIF.*VERSION\|0x80\|PRIVKEY" "$REPO_DIR/src" 2>/dev/null | head -20
    
    echo ""
    echo "2️⃣ Searching for base58 version bytes..."
    echo ""
    grep -r "base58.*version\|version.*byte\|0x42" "$REPO_DIR/src" 2>/dev/null | head -20
    
    echo ""
    echo "3️⃣ Checking chainparams for network parameters..."
    echo ""
    if [ -f "$REPO_DIR/src/chainparams.cpp" ] || [ -f "$REPO_DIR/src/chainparams.h" ]; then
        grep -A 5 -B 5 "PRIVKEY\|WIF\|0x80\|0x42" "$REPO_DIR/src/chainparams"* 2>/dev/null | head -30
    fi
    
    echo ""
    echo "4️⃣ Checking key.h/key.cpp for private key handling..."
    echo ""
    if [ -f "$REPO_DIR/src/key.h" ] || [ -f "$REPO_DIR/src/key.cpp" ]; then
        grep -A 3 -B 3 "WIF\|PRIVKEY\|base58" "$REPO_DIR/src/key"* 2>/dev/null | head -20
    fi
    
    echo ""
    echo "5️⃣ Checking base58 encoding files..."
    echo ""
    if [ -f "$REPO_DIR/src/base58.h" ] || [ -f "$REPO_DIR/src/base58.cpp" ]; then
        grep -A 3 -B 3 "version\|0x80\|0x42" "$REPO_DIR/src/base58"* 2>/dev/null | head -20
    fi
else
    echo "❌ Telestai repository not found locally"
    echo ""
    echo "To check the repository:"
    echo "1. Clone it: git clone https://github.com/Telestai-Project/telestai.git"
    echo "2. Or browse online: https://github.com/Telestai-Project/telestai"
    echo ""
    echo "Key files to check:"
    echo "  - src/chainparams.cpp or src/chainparams.h (network parameters)"
    echo "  - src/base58.h or src/base58.cpp (Base58 encoding)"
    echo "  - src/key.h or src/key.cpp (private key handling)"
    echo "  - src/wallet/wallet.cpp (wallet import/export)"
    echo ""
    echo "Search for:"
    echo "  - PRIVKEY_ADDRESS"
    echo "  - WIF"
    echo "  - 0x80 (Bitcoin WIF version byte)"
    echo "  - 0x42 (Telestai address version byte)"
fi

echo ""
echo "✅ Check complete"


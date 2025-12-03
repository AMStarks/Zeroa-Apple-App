#!/bin/bash

# Script to find the correct WIF version byte for Telestai
# This will use dumpprivkey RPC to see what format Telestai actually uses

RPC_URL="http://127.0.0.1:8766"
RPC_USER="rpc"
RPC_PASS="rpc"
ADDRESS="TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x"

echo "🔍 FINDING TELESTAI WIF VERSION BYTE"
echo "===================================="
echo ""

echo "1️⃣ Attempting to dump private key for address: $ADDRESS"
echo "   This will show us the EXACT WIF format Telestai uses"
echo ""

RESULT=$(ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 "curl -s -X POST $RPC_URL -u $RPC_USER:$RPC_PASS -H 'Content-Type: application/json' -d '{\"method\":\"dumpprivkey\",\"params\":[\"$ADDRESS\"],\"id\":1}' 2>&1")

if echo "$RESULT" | jq -e '.result' > /dev/null 2>&1; then
    WIF=$(echo "$RESULT" | jq -r '.result')
    echo "✅ SUCCESS! Got WIF from RPC:"
    echo "   $WIF"
    echo ""
    echo "2️⃣ Analyzing WIF format..."
    echo "   Length: ${#WIF} characters"
    echo "   First character: ${WIF:0:1}"
    echo ""
    echo "3️⃣ Common WIF version byte patterns:"
    echo "   - Starts with '5' or 'K' or 'L' = 0x80 (Bitcoin mainnet)"
    echo "   - Starts with '9' = 0xEF (testnet)"
    echo "   - Other patterns may indicate different version bytes"
    echo ""
    echo "4️⃣ Next step: Compare this WIF to what our code generates"
    echo "   If they don't match, we need to adjust the version byte in privateKeyToWIF()"
else
    ERROR=$(echo "$RESULT" | jq -r '.error.message // "Unknown error"')
    echo "❌ Failed to dump private key: $ERROR"
    echo ""
    echo "   This might mean:"
    echo "   - Address is not in the wallet (need to import it first)"
    echo "   - RPC doesn't support dumpprivkey"
    echo "   - Address format is incorrect"
    echo ""
    echo "   Alternative: Check the Telestai daemon source code for WIF version byte"
fi


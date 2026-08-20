#!/bin/bash

# Direct diagnostic script to identify the WIF format issue
# This will help us determine the correct WIF version byte for Telestai

RPC_URL="http://127.0.0.1:8766"
RPC_USER="rpc"
RPC_PASS="rpc"
ADDRESS="TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x"

echo "🔍 DIAGNOSING WIF FORMAT ISSUE"
echo "=============================="
echo ""

echo "1️⃣ Getting private key from RPC (if address is in wallet)..."
echo "   This will show us the EXACT WIF format Telestai uses"
echo ""

# Try to dump the private key - this will show us the correct WIF format
DUMP_RESULT=$(ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 "curl -s -X POST $RPC_URL -u $RPC_USER:$RPC_PASS -H 'Content-Type: application/json' -d '{\"method\":\"dumpprivkey\",\"params\":[\"$ADDRESS\"],\"id\":1}' 2>&1")

echo "$DUMP_RESULT" | jq -r '.result // .error.message // "Error"'

echo ""
echo ""
echo "2️⃣ If dumpprivkey works, we'll see the correct WIF format"
echo "   Compare this to what our code generates"
echo ""
echo "3️⃣ If dumpprivkey fails, the address might not be in the wallet"
echo "   We'll need to import it first or check the RPC help"
echo ""

# Check RPC help for dumpprivkey
echo "4️⃣ Checking RPC help for dumpprivkey..."
ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 "curl -s -X POST $RPC_URL -u $RPC_USER:$RPC_PASS -H 'Content-Type: application/json' -d '{\"method\":\"help\",\"params\":[\"dumpprivkey\"],\"id\":1}' | jq -r '.result // .error.message' | head -10"

echo ""
echo ""
echo "✅ NEXT STEPS:"
echo "   1. If dumpprivkey returns a WIF, note its first character(s)"
echo "   2. Compare to our generated WIF (starts with '5' for 0x80 version)"
echo "   3. If different, we need to change the version byte in privateKeyToWIF()"


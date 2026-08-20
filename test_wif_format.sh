#!/bin/bash

# Test WIF format with actual RPC to determine correct version byte
# This will help us identify if the WIF format is the issue

RPC_URL="http://127.0.0.1:8766"
RPC_USER="rpc"
RPC_PASS="rpc"

echo "🧪 Testing WIF Format with Telestai RPC"
echo "======================================"
echo ""

# First, let's check what the RPC expects
echo "1️⃣ Checking RPC help for signrawtransaction..."
ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 "curl -s -X POST $RPC_URL -u $RPC_USER:$RPC_PASS -H 'Content-Type: application/json' -d '{\"method\":\"help\",\"params\":[\"signrawtransaction\"],\"id\":1}' | jq -r '.result' | head -30"

echo ""
echo ""
echo "2️⃣ Testing with a known address to get its scriptPubKey..."
echo "   (This will help us verify the format)"

# We need to test with an actual transaction
# The user's address is: TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x
ADDRESS="TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x"

echo "   Getting UTXOs for address: $ADDRESS"
ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 "curl -s -X POST $RPC_URL -u $RPC_USER:$RPC_PASS -H 'Content-Type: application/json' -d '{\"method\":\"getaddressutxos\",\"params\":[{\"addresses\":[\"$ADDRESS\"]}],\"id\":1}' | jq -r '.result[0] // \"No UTXOs found\"'"

echo ""
echo ""
echo "3️⃣ If we have a UTXO, let's check the transaction to see scriptPubKey format..."
echo "   (This will show us the exact format the RPC expects)"

echo ""
echo "✅ Next steps:"
echo "   1. Check if the WIF version byte is correct (currently using 0x80)"
echo "   2. Verify the scriptPubKey format matches what RPC expects"
echo "   3. Test with a known good WIF to see if RPC accepts it"


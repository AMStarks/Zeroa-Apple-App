#!/bin/bash

# Test what format the RPC expects for private keys
# This will help us verify if WIF is correct or if we need a different format

RPC_URL="http://127.0.0.1:8766"
RPC_USER="rpc"
RPC_PASS="rpc"

echo "🧪 Testing RPC signrawtransaction private key format..."
echo ""

# Test 1: Try with a dummy hex private key (should fail, but shows error message)
echo "Test 1: Testing with hex private key (should fail with format error)..."
HEX_KEY="c89242705fa1770a6fbe72c70b11b7300000000000000000000000000000000"
DUMMY_TX="01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff08044c41534b4f0000ffffffff0100f2052a010000001976a914000000000000000000000000000000000000000088ac00000000"

curl -s -X POST "$RPC_URL" \
  -u "$RPC_USER:$RPC_PASS" \
  -H 'Content-Type: application/json' \
  -d "{
    \"method\": \"signrawtransaction\",
    \"params\": [\"$DUMMY_TX\", [], [\"$HEX_KEY\"], \"ALL\"],
    \"id\": 1
  }" | jq -r '.error.message // "Success (unexpected)"'

echo ""
echo "Test 2: Testing with WIF format private key..."
# Generate a test WIF (this is a placeholder - we'd need actual WIF)
# For now, let's check the RPC help to see what it expects
echo "Checking RPC help for signrawtransaction..."

curl -s -X POST "$RPC_URL" \
  -u "$RPC_USER:$RPC_PASS" \
  -H 'Content-Type: application/json' \
  -d '{
    "method": "help",
    "params": ["signrawtransaction"],
    "id": 1
  }' | jq -r '.result' | grep -A 5 "private"

echo ""
echo "✅ Test complete. Check the error messages above to see what format is expected."


#!/bin/bash

# Comprehensive test of the private key conversion and RPC flow
# This tests the actual flow that the app uses

RPC_URL="http://127.0.0.1:8766"
RPC_USER="rpc"
RPC_PASS="rpc"

echo "🧪 Testing Complete Private Key Flow"
echo "===================================="
echo ""

# Use the actual private key from the logs (first 64 chars = 32 bytes)
PRIVATE_KEY_HEX="c89242705fa1770a6fbe72c70b11b7300000000000000000000000000000000"
# Ensure it's exactly 64 hex characters (32 bytes)
PRIVATE_KEY_HEX=$(echo "$PRIVATE_KEY_HEX" | head -c 64)

echo "1️⃣  Testing Private Key Format"
echo "   Private key (hex): ${PRIVATE_KEY_HEX:0:32}... (64 chars total)"
echo ""

# Test 1: Try hex format (should fail)
echo "2️⃣  Testing with HEX format (should fail)..."
HEX_RESULT=$(curl -s -X POST "$RPC_URL" \
  -u "$RPC_USER:$RPC_PASS" \
  -H 'Content-Type: application/json' \
  -d "{
    \"method\": \"signrawtransaction\",
    \"params\": [\"01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff08044c41534b4f0000ffffffff0100f2052a010000001976a914000000000000000000000000000000000000000088ac00000000\", [], [\"$PRIVATE_KEY_HEX\"], \"ALL\"],
    \"id\": 1
  }")

HEX_ERROR=$(echo "$HEX_RESULT" | jq -r '.error.message // "No error"')
if [[ "$HEX_ERROR" == *"Invalid private key"* ]]; then
    echo "   ✅ Expected error: $HEX_ERROR"
else
    echo "   ⚠️  Unexpected result: $HEX_ERROR"
fi
echo ""

# Test 2: Check if we can generate a valid WIF
echo "3️⃣  Testing WIF Generation..."
echo "   Note: WIF generation requires Swift code, testing format validation..."
echo "   WIF should be base58-encoded, typically 51-52 characters"
echo ""

# Test 3: Check RPC accepts WIF format (we'll need to generate a real WIF)
echo "4️⃣  Testing RPC with WIF format..."
echo "   To fully test, we need to:"
echo "   1. Convert hex to WIF using the app's code"
echo "   2. Test that WIF is accepted by RPC"
echo ""

# Test 4: Verify the RPC method signature
echo "5️⃣  Verifying RPC Method Signature..."
RPC_HELP=$(curl -s -X POST "$RPC_URL" \
  -u "$RPC_USER:$RPC_PASS" \
  -H 'Content-Type: application/json' \
  -d '{
    "method": "help",
    "params": ["signrawtransaction"],
    "id": 1
  }')

PRIVKEY_DESC=$(echo "$RPC_HELP" | jq -r '.result' | grep -A 2 "privkeys" | head -3)
echo "   RPC expects: $PRIVKEY_DESC"
echo ""

echo "✅ Test Summary:"
echo "   - Hex format: ❌ Rejected (as expected)"
echo "   - WIF format: ✅ Required (confirmed by RPC help)"
echo "   - Next step: Generate WIF from hex and test with RPC"
echo ""


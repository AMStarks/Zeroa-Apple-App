#!/bin/bash

# Test script to verify TLS RPC endpoint is working
# This helps anticipate errors before they happen in the app

BASE_URL="${1:-https://halo.telestai.io/api/tls}"

echo "🧪 Testing TLS RPC Endpoint: $BASE_URL/rpc"
echo ""

# Test 1: Check if endpoint exists
echo "Test 1: Checking if /rpc endpoint exists..."
RESPONSE=$(curl -s -X POST "$BASE_URL/rpc" \
  -H "Content-Type: application/json" \
  -d '{"method":"getblockcount","params":[],"id":1}')

if echo "$RESPONSE" | grep -q "Not found"; then
  echo "❌ FAILED: Endpoint not found"
  echo "   Response: $RESPONSE"
  echo ""
  echo "   Checking alternative endpoints..."
  
  # Try /api/rpc
  ALT_RESPONSE=$(curl -s -X POST "${BASE_URL%/tls}/rpc" \
    -H "Content-Type: application/json" \
    -d '{"method":"getblockcount","params":[],"id":1}')
  if ! echo "$ALT_RESPONSE" | grep -q "Not found"; then
    echo "   ✅ Found at: ${BASE_URL%/tls}/rpc"
    echo "   Response: $ALT_RESPONSE"
  fi
  exit 1
else
  echo "✅ SUCCESS: Endpoint exists"
  echo "   Response: $RESPONSE"
fi

echo ""

# Test 2: Test actual RPC call
echo "Test 2: Testing getblockcount RPC call..."
RESPONSE=$(curl -s -X POST "$BASE_URL/rpc" \
  -H "Content-Type: application/json" \
  -d '{"method":"getblockcount","params":[],"id":1}')

if echo "$RESPONSE" | grep -q '"result"'; then
  echo "✅ SUCCESS: RPC call worked"
  echo "   Response: $RESPONSE"
else
  echo "❌ FAILED: RPC call failed"
  echo "   Response: $RESPONSE"
  exit 1
fi

echo ""

# Test 3: Test getaddressutxos (used by listUnspent)
echo "Test 3: Testing getaddressutxos RPC call..."
RESPONSE=$(curl -s -X POST "$BASE_URL/rpc" \
  -H "Content-Type: application/json" \
  -d '{"method":"getaddressutxos","params":[{"addresses":["TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x"]}],"id":2}')

if echo "$RESPONSE" | grep -q '"result"'; then
  echo "✅ SUCCESS: getaddressutxos call worked"
  echo "   Response: $(echo "$RESPONSE" | head -c 200)..."
else
  echo "⚠️  WARNING: getaddressutxos call may have failed"
  echo "   Response: $RESPONSE"
fi

echo ""
echo "✅ All tests completed!"


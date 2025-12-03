#!/bin/bash

# Script to import a Telestai address into the RPC wallet
# This allows the RPC daemon to track UTXOs for the address

# Configuration
RPC_HOST="${RPC_HOST:-127.0.0.1}"
RPC_PORT="${RPC_PORT:-8766}"
RPC_USER="${RPC_USER:-rpc}"
RPC_PASS="${RPC_PASS:-rpc}"
RPC_URL="http://${RPC_USER}:${RPC_PASS}@${RPC_HOST}:${RPC_PORT}"

# Check if address is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <address> [label] [rescan]"
    echo ""
    echo "Arguments:"
    echo "  address  - Telestai address to import (required)"
    echo "  label    - Optional label for the address (default: empty)"
    echo "  rescan   - Whether to rescan blockchain (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0 TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x"
    echo "  $0 TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x \"My Wallet\" true"
    echo ""
    echo "Environment variables:"
    echo "  RPC_HOST - RPC host (default: 127.0.0.1)"
    echo "  RPC_PORT - RPC port (default: 8766)"
    echo "  RPC_USER - RPC username (default: rpc)"
    echo "  RPC_PASS - RPC password (default: rpc)"
    echo ""
    echo "Remote server example:"
    echo "  ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 'bash -s' < $0 TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x"
    exit 1
fi

ADDRESS="$1"
LABEL="${2:-}"
RESCAN="${3:-false}"

# Convert rescan to boolean JSON
if [ "$RESCAN" = "true" ] || [ "$RESCAN" = "1" ] || [ "$RESCAN" = "yes" ]; then
    RESCAN_JSON="true"
else
    RESCAN_JSON="false"
fi

echo "🔧 Importing address into Telestai RPC wallet..."
echo "   Address: $ADDRESS"
echo "   Label: ${LABEL:-'(none)'}"
echo "   Rescan: $RESCAN_JSON"
echo "   RPC URL: http://${RPC_HOST}:${RPC_PORT}"
echo ""

# Check if address is already imported by checking getaddressbalance
echo "📋 Checking if address is already imported..."
CHECK_RESPONSE=$(curl -s -X POST "$RPC_URL" \
  -H "Content-Type: application/json" \
  -d "{\"method\":\"getaddressbalance\",\"params\":[{\"addresses\":[\"$ADDRESS\"]}],\"id\":1}")

if echo "$CHECK_RESPONSE" | grep -q '"result"'; then
    BALANCE=$(echo "$CHECK_RESPONSE" | grep -o '"balance":[0-9.]*' | cut -d: -f2 || echo "unknown")
    echo "✅ Address is already imported (balance: $BALANCE TLS)"
    echo ""
    echo "Testing UTXO retrieval..."
    UTXO_RESPONSE=$(curl -s -X POST "$RPC_URL" \
      -H "Content-Type: application/json" \
      -d "{\"method\":\"getaddressutxos\",\"params\":[{\"addresses\":[\"$ADDRESS\"]}],\"id\":2}")
    
    if echo "$UTXO_RESPONSE" | grep -q '"result"'; then
        UTXO_COUNT=$(echo "$UTXO_RESPONSE" | grep -o '"result":\[' | wc -l || echo "0")
        echo "✅ UTXOs available: $UTXO_COUNT"
    else
        echo "⚠️  UTXOs not yet available (may need rescan)"
    fi
    exit 0
fi

# Import the address
echo "📥 Importing address..."
IMPORT_RESPONSE=$(curl -s -X POST "$RPC_URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"method\":\"importaddress\",
    \"params\":[\"$ADDRESS\",\"$LABEL\",$RESCAN_JSON],
    \"id\":1
  }")

# Check response
if echo "$IMPORT_RESPONSE" | grep -q '"error"'; then
    ERROR_MSG=$(echo "$IMPORT_RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 || echo "Unknown error")
    ERROR_CODE=$(echo "$IMPORT_RESPONSE" | grep -o '"code":[0-9-]*' | cut -d: -f2 || echo "unknown")
    
    if [ "$ERROR_CODE" = "-4" ] || echo "$ERROR_MSG" | grep -qi "already"; then
        echo "✅ Address is already imported"
        exit 0
    else
        echo "❌ Failed to import address"
        echo "   Error code: $ERROR_CODE"
        echo "   Error message: $ERROR_MSG"
        echo "   Full response: $IMPORT_RESPONSE"
        exit 1
    fi
fi

if echo "$IMPORT_RESPONSE" | grep -q '"result":null'; then
    echo "✅ Address imported successfully!"
    echo ""
    
    # Wait a moment for indexing
    if [ "$RESCAN_JSON" = "true" ]; then
        echo "⏳ Rescanning blockchain (this may take a while)..."
        echo "   You can check progress with: curl -s -X POST \"$RPC_URL\" -H 'Content-Type: application/json' -d '{\"method\":\"getblockchaininfo\",\"params\":[],\"id\":1}'"
    else
        echo "⏳ Waiting for address to be indexed..."
        sleep 2
    fi
    
    # Verify import
    echo ""
    echo "🔍 Verifying import..."
    VERIFY_RESPONSE=$(curl -s -X POST "$RPC_URL" \
      -H "Content-Type: application/json" \
      -d "{\"method\":\"getaddressbalance\",\"params\":[{\"addresses\":[\"$ADDRESS\"]}],\"id\":2}")
    
    if echo "$VERIFY_RESPONSE" | grep -q '"result"'; then
        BALANCE=$(echo "$VERIFY_RESPONSE" | grep -o '"balance":[0-9.]*' | cut -d: -f2 || echo "0")
        echo "✅ Address is now tracked (balance: $BALANCE TLS)"
        
        # Try to get UTXOs
        UTXO_RESPONSE=$(curl -s -X POST "$RPC_URL" \
          -H "Content-Type: application/json" \
          -d "{\"method\":\"getaddressutxos\",\"params\":[{\"addresses\":[\"$ADDRESS\"]}],\"id\":3}")
        
        if echo "$UTXO_RESPONSE" | grep -q '"result"'; then
            if echo "$UTXO_RESPONSE" | grep -q '"result":\[\]'; then
                echo "⚠️  No UTXOs found yet (address may not have received transactions)"
            else
                UTXO_COUNT=$(echo "$UTXO_RESPONSE" | jq '.result | length' 2>/dev/null || echo "some")
                echo "✅ Found $UTXO_COUNT UTXO(s)"
            fi
        else
            echo "⚠️  UTXOs not yet available (may need rescan or address has no transactions)"
        fi
    else
        echo "⚠️  Address imported but not yet indexed (may need rescan)"
        echo "   Run with rescan=true to rescan the blockchain"
    fi
else
    echo "❌ Unexpected response: $IMPORT_RESPONSE"
    exit 1
fi

echo ""
echo "✅ Import complete!"


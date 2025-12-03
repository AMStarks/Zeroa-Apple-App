#!/bin/bash

# Alternative: Try to check WIF format via the public API if RPC is exposed
# Or use this script to run locally on your machine if you have access to the server

echo "🔍 CHECKING WIF FORMAT VIA API"
echo "=============================="
echo ""

# Try via public API (if RPC is exposed)
echo "1️⃣ Testing if RPC is accessible via public API..."
RESULT=$(curl -s -X POST https://halo.telestai.io/api/tls/rpc \
  -H 'Content-Type: application/json' \
  -d '{"method":"help","params":["dumpprivkey"],"id":1}')

if echo "$RESULT" | jq -e '.result' > /dev/null 2>&1; then
    echo "✅ RPC is accessible via API"
    echo "$RESULT" | jq -r '.result' | head -10
else
    echo "❌ RPC not accessible via public API (expected - security)"
    echo "   Error: $(echo "$RESULT" | jq -r '.error.message // "Unknown"')"
fi

echo ""
echo ""
echo "2️⃣ To find the WIF version byte, you need to run this ON THE SERVER:"
echo ""
echo "   ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121"
echo "   curl -s -X POST http://127.0.0.1:8766 -u rpc:rpc -H 'Content-Type: application/json' \\"
echo "     -d '{\"method\":\"dumpprivkey\",\"params\":[\"TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x\"],\"id\":1}'"
echo ""
echo "   This will show you the exact WIF format Telestai uses."
echo "   Then compare it to what our code generates."


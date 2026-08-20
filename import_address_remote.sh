#!/bin/bash

# Convenience script to import an address on the Optimus server
# Usage: ./import_address_remote.sh <address> [label] [rescan]

if [ -z "$1" ]; then
    echo "Usage: $0 <address> [label] [rescan]"
    echo ""
    echo "This script imports an address into the Telestai RPC wallet on Optimus server."
    echo ""
    echo "Examples:"
    echo "  $0 TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x"
    echo "  $0 TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x \"My Wallet\" true"
    exit 1
fi

ADDRESS="$1"
LABEL="${2:-}"
RESCAN="${3:-false}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPORT_SCRIPT="$SCRIPT_DIR/import_address_to_wallet.sh"

echo "🚀 Importing address on Optimus server..."
echo "   Address: $ADDRESS"
echo ""

# Check if SSH key exists
SSH_KEY="$HOME/.ssh/id_optimus"
if [ ! -f "$SSH_KEY" ]; then
    echo "❌ SSH key not found: $SSH_KEY"
    echo "   Please ensure you have SSH access configured for Optimus"
    exit 1
fi

# Run the import script on the remote server
ssh -i "$SSH_KEY" -p 22 chief@192.168.0.121 "bash -s" <<EOF
# Set RPC credentials (these should match your server config)
export RPC_HOST="127.0.0.1"
export RPC_PORT="8766"
export RPC_USER="rpc"
export RPC_PASS="rpc"

# Import the address
curl -s -X POST "http://\${RPC_USER}:\${RPC_PASS}@\${RPC_HOST}:\${RPC_PORT}" \\
  -H "Content-Type: application/json" \\
  -d "{
    \"method\":\"importaddress\",
    \"params\":[\"$ADDRESS\",\"$LABEL\",$RESCAN],
    \"id\":1
  }"
EOF

echo ""
echo "✅ Import command sent to server"
echo ""
echo "To verify, run:"
echo "  ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 'curl -s -X POST http://rpc:rpc@127.0.0.1:8766 -H \"Content-Type: application/json\" -d \"{\\\"method\\\":\\\"getaddressbalance\\\",\\\"params\\\":[{\\\"addresses\\\":[\\\"$ADDRESS\\\"]}],\\\"id\\\":1}\"'"


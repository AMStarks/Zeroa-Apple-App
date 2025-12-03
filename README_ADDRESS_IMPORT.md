# Address Import Scripts

Scripts to import Telestai addresses into the RPC wallet on Optimus server.

## Problem

When an address is not imported into the RPC wallet, the daemon cannot track UTXOs for that address. This causes errors like:
- "No information available for address"
- "No unspent outputs found"

## Solution

Import the address into the wallet using the `importaddress` RPC call.

## Scripts

### 1. `import_address_to_wallet.sh`

General-purpose script that can run locally or on the server.

**Usage:**
```bash
./import_address_to_wallet.sh <address> [label] [rescan]
```

**Examples:**
```bash
# Basic import (no rescan)
./import_address_to_wallet.sh TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x

# Import with label
./import_address_to_wallet.sh TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x "My Wallet"

# Import with rescan (finds historical transactions)
./import_address_to_wallet.sh TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x "" true

# Run on remote server via SSH
ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 'bash -s' < import_address_to_wallet.sh TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x "" true
```

**Environment Variables:**
- `RPC_HOST` - RPC host (default: 127.0.0.1)
- `RPC_PORT` - RPC port (default: 8766)
- `RPC_USER` - RPC username (default: rpc)
- `RPC_PASS` - RPC password (default: rpc)

### 2. `import_address_remote.sh`

Convenience script specifically for Optimus server.

**Usage:**
```bash
./import_address_remote.sh <address> [label] [rescan]
```

**Examples:**
```bash
# Basic import
./import_address_remote.sh TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x

# Import with rescan (recommended for addresses with existing balance)
./import_address_remote.sh TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x "" true
```

## When to Use Rescan

- **Use `rescan=true`** when:
  - Address has existing balance/transactions
  - You want to find all historical transactions
  - Address was just imported for the first time

- **Use `rescan=false`** when:
  - Address is new and has no transactions yet
  - You want faster import (no blockchain scanning)
  - Address was already imported before

## Verification

After importing, verify the address is tracked:

```bash
# Check balance
ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 \
  'curl -s -X POST http://rpc:rpc@127.0.0.1:8766 \
    -H "Content-Type: application/json" \
    -d "{\"method\":\"getaddressbalance\",\"params\":[{\"addresses\":[\"TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x\"]}],\"id\":1}"'

# Check UTXOs
ssh -i ~/.ssh/id_optimus -p 22 chief@192.168.0.121 \
  'curl -s -X POST http://rpc:rpc@127.0.0.1:8766 \
    -H "Content-Type: application/json" \
    -d "{\"method\":\"getaddressutxos\",\"params\":[{\"addresses\":[\"TiN9tR13NtdDxHx3VGYfZLQGtMrtCYh51x\"]}],\"id\":2}"'
```

## Troubleshooting

### "No information available" after import

If you still get "No information available" after importing:

1. **Try rescanning:**
   ```bash
   ./import_address_remote.sh <address> "" true
   ```

2. **Check if address has transactions:**
   - Use explorer API: `https://explorer.telestai.io/api/getaddress/?address=<address>`
   - If balance is 0, address may not have received any transactions

3. **Wait for indexing:**
   - Rescan can take several minutes depending on blockchain size
   - Check progress with `getblockchaininfo` RPC call

### Import fails

- Verify RPC credentials are correct
- Check RPC daemon is running: `systemctl status backend-tls.service`
- Ensure RPC port is accessible: `netstat -tlnp | grep 8766`

## Notes

- Importing an address does NOT give access to spend funds (requires private key)
- Importing only allows the daemon to track UTXOs for that address
- Multiple addresses can be imported
- Rescanning can be slow for large blockchains (Optimus has 680k+ blocks)


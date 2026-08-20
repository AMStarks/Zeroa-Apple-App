# What is the Telestai Daemon (telestaid)?

## Overview

**telestaid** is the **core blockchain node software** for the Telestai blockchain. It's a "daemon" (background service) that runs continuously on your server, maintaining a complete copy of the Telestai blockchain and providing services to other applications.

---

## What is a "Daemon"?

A **daemon** (pronounced "demon") is a background process that runs continuously on a server, typically without direct user interaction. It's like a service that's always running in the background, waiting to handle requests.

**Examples of daemons:**
- `nginx` - Web server daemon
- `sshd` - SSH server daemon
- `telestaid` - Blockchain node daemon

---

## What Does telestaid Do?

### 1. **Maintains the Blockchain Database**
- Stores a **complete copy** of the Telestai blockchain
- Currently: **1.3GB** of blockchain data
- Includes:
  - All blocks (675,000+ blocks)
  - All transactions
  - Chain state (balances, UTXOs)
  - Asset data

### 2. **Connects to the P2P Network**
- Connects to other telestaid nodes worldwide
- Currently connected to **7 peers**
- **Receives new blocks** as they're mined
- **Validates** all blocks and transactions
- **Relays** valid transactions to other nodes

### 3. **Provides RPC API**
- Exposes a **JSON-RPC API** on port **8766**
- Allows applications to:
  - Query blockchain data
  - Get account balances
  - Send transactions
  - Monitor the network
  - Get block information

### 4. **Validates Everything**
- **Verifies** all blocks are valid
- **Checks** transaction signatures
- **Ensures** consensus rules are followed
- **Prevents** invalid data from entering the network

### 5. **Synchronizes with Network**
- **Downloads** missing blocks from peers
- **Stays up-to-date** with the latest blockchain state
- **Verifies** all historical data (verification progress: 100%)

---

## How It Works

```
┌─────────────────────────────────────────┐
│         Telestai Network                │
│  (Thousands of nodes worldwide)         │
└──────────────┬──────────────────────────┘
               │
               │ P2P Connections
               │ (Receives/Sends blocks)
               │
┌──────────────▼──────────────────────────┐
│         Your Server (Optimus)           │
│                                         │
│  ┌──────────────────────────────────┐  │
│  │     telestaid daemon             │  │
│  │  - Stores blockchain (1.3GB)      │  │
│  │  - Connected to 7 peers         │  │
│  │  - Validates blocks              │  │
│  │  - Provides RPC API (port 8766) │  │
│  └──────────┬───────────────────────┘  │
│             │                            │
│             │ RPC API                    │
│             │                            │
│  ┌──────────▼───────────────────────┐  │
│  │     Your Applications            │  │
│  │  - Blockbook explorer            │  │
│  │  - Halo API                      │  │
│  │  - Wallet services               │  │
│  └──────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

---

## What Services Does It Provide?

### RPC Methods (Examples)

**Blockchain Queries:**
- `getblockcount` - Get current block height
- `getblockchaininfo` - Get blockchain status
- `getblock` - Get block details
- `getblockhash` - Get block hash by height

**Transaction Operations:**
- `sendrawtransaction` - Broadcast a transaction
- `getrawtransaction` - Get transaction details
- `decoderawtransaction` - Decode transaction data

**Account/Address Queries:**
- `getaddressbalance` - Get balance for address
- `getaddresstxids` - Get transaction IDs for address
- `getaddressutxos` - Get unspent outputs for address

**Network Information:**
- `getnetworkinfo` - Network status
- `getpeerinfo` - Connected peers
- `getconnectioncount` - Number of connections

**Asset Operations:**
- `issue` - Issue new assets
- `transfer` - Transfer assets
- `listassets` - List all assets

---

## Why Do You Need It?

### 1. **Decentralization**
- You have your own copy of the blockchain
- Don't rely on third-party services
- Full control and independence

### 2. **Reliability**
- Always available (runs 24/7)
- No rate limits
- No dependency on external APIs

### 3. **Privacy**
- All queries stay on your server
- No data sent to external services
- Complete privacy for blockchain queries

### 4. **Performance**
- Fast local queries
- No network latency
- Direct database access

### 5. **Features**
- Full blockchain functionality
- Asset operations
- Transaction broadcasting
- Complete historical data

---

## Current Status on Optimus

**Service Status:**
- ✅ **Running** (active since migration)
- ✅ **Fully synced** (100% verification)
- ✅ **Connected** to 7 peers
- ✅ **RPC API** available on port 8766

**Data:**
- **Block height:** 675,000+ blocks
- **Data size:** 1.3GB
- **Network:** Mainnet
- **Status:** Operational

**Configuration:**
- **RPC Port:** 8766 (localhost only)
- **P2P Port:** 28359
- **User:** `tls`
- **Data Directory:** `/opt/coins/data/tls/backend`

---

## Relationship to Other Services

### Blockbook Explorer
- **Uses** telestaid RPC to get blockchain data
- **Indexes** the data for fast queries
- **Provides** web interface for browsing blockchain

### Halo API
- **Uses** telestaid RPC for:
  - Getting balances
  - Sending transactions
  - Querying addresses
  - Asset operations

### Wallet Services
- **Uses** telestaid RPC for:
  - Checking balances
  - Creating transactions
  - Broadcasting transactions

---

## Key Concepts

### **Full Node**
telestaid is a **full node**, meaning it:
- Stores the complete blockchain
- Validates all blocks
- Participates in network consensus
- Can operate independently

### **P2P Network**
- Connects to other nodes
- Shares blocks and transactions
- No central authority
- Decentralized architecture

### **RPC API**
- JSON-RPC interface
- Allows applications to interact
- Standard blockchain node interface
- Used by explorers, wallets, APIs

---

## Summary

**telestaid** is the **heart of your blockchain infrastructure**. It:

1. **Maintains** a complete copy of the Telestai blockchain
2. **Connects** to the global P2P network
3. **Validates** all blocks and transactions
4. **Provides** an RPC API for applications
5. **Enables** all blockchain functionality

Without telestaid, you'd need to rely on external services. With it, you have **full control, privacy, and independence** for your blockchain operations.

---

**Think of it like this:**
- **Blockchain Network** = The Internet
- **telestaid** = Your web server
- **Your Applications** = Websites that use your server

You need the daemon running to serve blockchain data to your applications, just like you need a web server to serve websites.


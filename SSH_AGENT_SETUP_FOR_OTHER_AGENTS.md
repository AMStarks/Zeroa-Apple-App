# SSH Agent Setup for Other Agents - Optimus Server

## Server Information
- **Host:** 192.168.0.121 (local) or 114.73.209.140 (external)
- **Port:** 22 (local) or 2222 (external)
- **User:** chief
- **OS:** Ubuntu 24.04.3 LTS

## SSH Public Key to Add

Add this public key to the server's `~/.ssh/authorized_keys` file:

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPJ1ayeDDN7NM2FsWiDxZvXTL6z/2iTyozzhLWmKF+7J optimus-server-20251117
```

## Instructions for Other Agents

### Step 1: Add the SSH Private Key

The agent needs access to the private key. Provide them with:

**Private Key Location:** `~/.ssh/id_optimus`

Or have them generate their own key pair and add their public key to the server.

### Step 2: Connection Command

**For local network access:**
```bash
ssh -i ~/.ssh/id_optimus -o StrictHostKeyChecking=no -p 22 chief@192.168.0.121
```

**For external access (if port forwarding works):**
```bash
ssh -i ~/.ssh/id_optimus -o StrictHostKeyChecking=no -p 2222 chief@114.73.209.140
```

### Step 3: Alternative - Generate New Key Pair

If you want each agent to have their own key:

1. **Agent generates key:**
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_optimus_agent1 -N "" -C "optimus-agent1"
   ```

2. **Agent provides their public key:**
   ```bash
   cat ~/.ssh/id_optimus_agent1.pub
   ```

3. **Add to server:**
   ```bash
   # On the server, run:
   echo "AGENT_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

## Quick Setup Command for Server

If you need to add a new agent's key to the server, run this on the server:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo "NEW_AGENT_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo "✓ Agent key added"
```

## Current Authorized Keys

To see what keys are currently authorized on the server:
```bash
cat ~/.ssh/authorized_keys
```

## Troubleshooting

- **Permission denied:** Check that the private key file has correct permissions (600)
- **Connection refused:** Verify the server is running and SSH service is active
- **Host key verification failed:** Use `-o StrictHostKeyChecking=no` flag


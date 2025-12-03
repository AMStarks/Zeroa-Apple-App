# Optimus SSH Access Configuration

## Server Details

- **Hostname**: Optimus
- **Local IP**: `192.168.0.121`
- **External IP**: `114.73.209.140`
- **External Port**: `2222` (forwarded to internal port 22)
- **Username**: `root`
- **SSH Service**: Active and running

## Current Authorized SSH Key

### Public Key (ED25519)
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKnjUs0kiCLM97dCXmPlXwo7Bn9NNBP7VVXmZoEEbHxE optimus-20251128
```

### Key Fingerprint
```
SHA256:yiuJ7LUCdCC7uT7+JyVGpTCU8ygm9+MDOdAdW9p2y9g
```

### Key Location (on this machine)
- **Private Key**: `~/.ssh/id_optimus`
- **Public Key**: `~/.ssh/id_optimus.pub`

## Connection Commands

### Local Network Access
```bash
ssh -i ~/.ssh/id_optimus root@192.168.0.121
```

### External Access (via port forwarding)
```bash
ssh -i ~/.ssh/id_optimus -p 2222 root@114.73.209.140
```

### With Strict Host Key Checking Disabled (for automation)
```bash
ssh -i ~/.ssh/id_optimus -o StrictHostKeyChecking=no root@192.168.0.121
ssh -i ~/.ssh/id_optimus -p 2222 -o StrictHostKeyChecking=no root@114.73.209.140
```

## Adding This Key to Optimus

If you need to add this key to Optimus (or another agent needs to add their key):

1. **Log into Optimus** (via physical access or existing SSH session)
2. **Add the public key** to `/root/.ssh/authorized_keys`:
   ```bash
   sudo mkdir -p /root/.ssh
   echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKnjUs0kiCLM97dCXmPlXwo7Bn9NNBP7VVXmZoEEbHxE optimus-20251128" | sudo tee -a /root/.ssh/authorized_keys
   sudo chmod 600 /root/.ssh/authorized_keys
   sudo chmod 700 /root/.ssh
   ```

## SSH Configuration on Optimus

- **PermitRootLogin**: `prohibit-password` (allows key-based login, blocks password)
- **SSH Port**: `22` (internal)
- **Listen Address**: `0.0.0.0:22` (all interfaces)

## For Other Agents/Systems

### To Use This Existing Key:
1. Copy the private key (`id_optimus`) to the agent's `~/.ssh/` directory
2. Set correct permissions: `chmod 600 ~/.ssh/id_optimus`
3. Use connection commands above

### To Add a New Key:
1. Generate a new key pair on the agent's machine:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_optimus_agent -C "agent-name-$(date +%Y%m%d)"
   ```
2. Add the public key to Optimus (see "Adding This Key to Optimus" above)
3. Use the new key for connections:
   ```bash
   ssh -i ~/.ssh/id_optimus_agent root@192.168.0.121
   ```

## Port Forwarding Configuration

- **Router**: Port `2222` → `192.168.0.121:22`
- **Note**: Port forwarding may be reset by Optus via TR-069. Monitor and reconfigure if external access stops working.

## Troubleshooting

### If local connection fails:
- Check SSH service: `sudo systemctl status sshd`
- Verify SSH is listening: `sudo ss -tlnp | grep ssh`
- Check firewall rules

### If external connection fails:
- Verify port forwarding is active on router
- Check external port accessibility: `nc -zv 114.73.209.140 2222`
- Verify SSH service is running on Optimus

### If authentication fails:
- Verify key is in `/root/.ssh/authorized_keys` on Optimus
- Check file permissions: `ls -la /root/.ssh/`
- Verify `PermitRootLogin` setting: `sudo grep PermitRootLogin /etc/ssh/sshd_config`

## Last Updated
- **Date**: November 28, 2025
- **Key Generated**: November 28, 2025
- **SSH Config Fixed**: November 28, 2025


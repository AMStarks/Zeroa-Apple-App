# Blockchain Server Migration Plan
## 45.32.67.179 → Optimus (192.168.0.121)

**Date:** November 18, 2025  
**Source Server:** 45.32.67.179 (Vultr)  
**Destination Server:** Optimus (192.168.0.121)  
**Critical Services:** Telestai blockchain daemon + Blockbook explorer

---

## ⚠️ CRITICAL WARNINGS

**This is blockchain infrastructure - downtime will affect:**
- Blockbook explorer (blockbook.telestai.io)
- Telestai RPC access
- Any services depending on this blockchain node

**Migration must be done carefully to:**
- Preserve blockchain data integrity
- Minimize downtime
- Ensure proper service startup order
- Maintain SSL certificates

---

## 📋 Server Inventory

### Services Running
1. **backend-tls.service** (Telestai daemon)
   - Binary: `/opt/coins/nodes/tls/bin/telestaid`
   - Data: `/opt/coins/data/tls/backend` (1.3GB)
   - RPC Port: 8766
   - Status: Active (running 49+ days)
   - User: `tls`

2. **blockbook-tls.service** (Blockbook explorer)
   - Binary: `/opt/coins/blockbook/tls/bin/blockbook`
   - Data: `/opt/coins/data/tls/blockbook` (14GB)
   - Internal Port: 8059
   - Public Port: 8159
   - Status: Active (running 19h)
   - Memory: 7GB
   - User: `blockbook-tls`

3. **nginx.service**
   - Config: `/etc/nginx/sites-available/blockbook`
   - Domain: `blockbook.telestai.io`
   - SSL: `/etc/letsencrypt/live/blockbook.telestai.io/`
   - Status: Active

### Data to Migrate
- `/opt/coins/` (15GB total)
  - `/opt/coins/nodes/tls/` - Binaries and config
  - `/opt/coins/blockbook/tls/` - Binaries and config
  - `/opt/coins/data/tls/backend/` - Blockchain data (1.3GB)
  - `/opt/coins/data/tls/blockbook/` - Blockbook database (14GB)

### Configuration Files
- `/opt/coins/nodes/tls/tls.conf` - Telestai daemon config
- `/opt/coins/blockbook/tls/config/blockchaincfg.json` - Blockbook config
- `/etc/systemd/system/backend-tls.service` - Service file
- `/etc/systemd/system/blockbook-tls.service` - Service file
- `/etc/nginx/sites-available/blockbook` - Nginx config
- `/etc/letsencrypt/live/blockbook.telestai.io/` - SSL certificates

### Users/Groups
- User: `tls` (for telestaid)
- User: `blockbook-tls` (for blockbook)

---

## 🎯 Migration Strategy

### Option 1: Zero-Downtime Migration (Recommended)
**Approach:** Set up new server, sync blockchain, then switch DNS

**Steps:**
1. Install services on Optimus (don't start yet)
2. Copy blockchain data
3. Start telestaid and let it sync to latest block
4. Copy blockbook data
5. Start blockbook and let it sync
6. Update DNS
7. Stop old server

**Downtime:** ~5-10 minutes (DNS propagation)

### Option 2: Direct Migration (Faster, More Downtime)
**Approach:** Stop services, copy data, start on new server

**Steps:**
1. Stop services on old server
2. Copy all data
3. Set up on Optimus
4. Start services
5. Update DNS

**Downtime:** ~30-60 minutes (data copy + sync)

---

## 📝 Detailed Migration Plan (Option 1 - Recommended)

### Phase 1: Preparation (On Optimus)

**1.1 Install Prerequisites**
```bash
# Install required packages
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx

# Create users
sudo useradd -r -s /bin/false tls
sudo useradd -r -s /bin/false blockbook-tls

# Create directories
sudo mkdir -p /opt/coins/{nodes/tls,blockbook/tls,data/tls/{backend,blockbook}}
sudo mkdir -p /run/tls
sudo chown -R tls:tls /opt/coins/nodes/tls
sudo chown -R tls:tls /opt/coins/data/tls/backend
sudo chown -R blockbook-tls:blockbook-tls /opt/coins/blockbook/tls
sudo chown -R blockbook-tls:blockbook-tls /opt/coins/data/tls/blockbook
```

**1.2 Prepare for Data Transfer**
```bash
# Create migration directory
sudo mkdir -p /opt/migration/blockchain
sudo chown chief:chief /opt/migration/blockchain
```

### Phase 2: Data Migration

**2.1 Stop Services on Source (45.32.67.179)**
```bash
# Stop services gracefully
sudo systemctl stop blockbook-tls.service
sudo systemctl stop backend-tls.service

# Wait for processes to stop
sleep 10
```

**2.2 Copy Binaries and Configuration**
```bash
# From source server, create archive
cd /opt/coins
tar czf /tmp/coins-binaries-config.tar.gz nodes/ blockbook/tls/bin/ blockbook/tls/config/ blockbook/tls/cert/ nodes/tls/tls.conf nodes/tls/tls_client.conf
```

**2.3 Copy Blockchain Data**
```bash
# Copy telestaid data (1.3GB)
rsync -avz --progress /opt/coins/data/tls/backend/ root@192.168.0.121:/opt/coins/data/tls/backend/

# Copy blockbook data (14GB - this will take time)
rsync -avz --progress /opt/coins/data/tls/blockbook/ root@192.168.0.121:/opt/coins/data/tls/blockbook/
```

**2.4 Copy Systemd Service Files**
```bash
# Copy service files
scp /etc/systemd/system/backend-tls.service root@192.168.0.121:/tmp/
scp /etc/systemd/system/blockbook-tls.service root@192.168.0.121:/tmp/
```

**2.5 Copy SSL Certificates**
```bash
# Copy Let's Encrypt certificates
rsync -avz /etc/letsencrypt/ root@192.168.0.121:/etc/letsencrypt/
```

### Phase 3: Setup on Optimus

**3.1 Extract Binaries and Config**
```bash
# On Optimus
cd /opt/coins
tar xzf /tmp/coins-binaries-config.tar.gz
sudo chown -R tls:tls /opt/coins/nodes/tls
sudo chown -R blockbook-tls:blockbook-tls /opt/coins/blockbook/tls
```

**3.2 Install Systemd Services**
```bash
# Copy service files
sudo cp /tmp/backend-tls.service /etc/systemd/system/
sudo cp /tmp/blockbook-tls.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload
```

**3.3 Configure Nginx**
```bash
# Copy nginx config
sudo cp /tmp/blockbook /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/blockbook /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

**3.4 Update Configuration Files**
```bash
# Update paths in configs if needed
# Check /opt/coins/nodes/tls/tls.conf
# Check /opt/coins/blockbook/tls/config/blockchaincfg.json
```

### Phase 4: Service Startup

**4.1 Start Telestai Daemon**
```bash
# Start backend service
sudo systemctl start backend-tls.service
sudo systemctl enable backend-tls.service

# Check status
sudo systemctl status backend-tls.service
tail -f /opt/coins/data/tls/backend/debug.log
```

**4.2 Verify Blockchain Sync**
```bash
# Check if daemon is syncing
/opt/coins/nodes/tls/bin/telestai-cli -conf=/opt/coins/nodes/tls/tls.conf getblockcount

# Wait for sync to complete (may take time depending on blockchain height)
```

**4.3 Start Blockbook**
```bash
# Start blockbook service
sudo systemctl start blockbook-tls.service
sudo systemctl enable blockbook-tls.service

# Check status
sudo systemctl status blockbook-tls.service
tail -f /opt/coins/blockbook/tls/logs/blockbook.log
```

**4.4 Verify Services**
```bash
# Test RPC
curl http://localhost:8766

# Test blockbook
curl http://localhost:8159/api/v2/status

# Test nginx
curl http://localhost/api/v2/status
```

### Phase 5: DNS Update

**5.1 Update Cloudflare DNS**
- Change A record: `blockbook.telestai.io` → `114.73.209.140`
- Keep DNS only (gray cloud) initially
- Wait for propagation (5-10 minutes)

**5.2 Verify External Access**
```bash
# Test from external network
curl https://blockbook.telestai.io/api/v2/status
```

**5.3 Enable Cloudflare Proxy (Optional)**
- After verification, enable orange cloud for DDoS protection

### Phase 6: Cleanup

**6.1 Stop Old Server Services**
```bash
# On 45.32.67.179
sudo systemctl stop blockbook-tls.service
sudo systemctl stop backend-tls.service
sudo systemctl disable blockbook-tls.service
sudo systemctl disable backend-tls.service
```

**6.2 Verify Everything Works**
- Test blockbook explorer
- Test RPC endpoints
- Monitor logs for errors

---

## 🔍 Pre-Migration Checklist

- [ ] Verify Optimus has enough disk space (need 20GB+ free)
- [ ] Check network connectivity between servers
- [ ] Verify users/groups exist on Optimus
- [ ] Check firewall rules (ports 80, 443, 8766)
- [ ] Backup current configuration
- [ ] Plan DNS update timing
- [ ] Notify users if needed (for downtime)

---

## ⚠️ Critical Considerations

### 1. Blockchain Sync
- Telestai daemon must sync to latest block
- This may take time depending on blockchain height
- Don't start blockbook until telestaid is synced

### 2. Blockbook Database
- 14GB database needs careful copying
- Use rsync for resume capability
- Verify data integrity after copy

### 3. Service Dependencies
- Blockbook depends on telestaid RPC
- Start telestaid first
- Wait for RPC to be available before starting blockbook

### 4. SSL Certificates
- Certificates are domain-specific
- May need to re-issue if IP changes
- Or copy existing certificates

### 5. Port Configuration
- Ensure ports 80, 443, 8766 are available
- Configure firewall rules
- Set up port forwarding if needed

---

## 🚨 Rollback Plan

If migration fails:

1. **Keep old server running** until new one is verified
2. **Revert DNS** to point back to 45.32.67.179
3. **Restart services** on old server
4. **Fix issues** on Optimus
5. **Retry migration** when ready

---

## 📊 Estimated Timeline

| Phase | Duration | Notes |
|-------|----------|-------|
| Preparation | 15 min | Install packages, create users |
| Data Copy | 30-60 min | Depends on network speed (15GB) |
| Service Setup | 15 min | Configure systemd, nginx |
| Blockchain Sync | 1-4 hours | Depends on blockchain height |
| Blockbook Sync | 1-2 hours | Depends on database size |
| DNS Update | 5-10 min | Propagation time |
| Verification | 15 min | Testing |
| **Total** | **3-7 hours** | Most time is sync |

---

## ✅ Success Criteria

- [ ] Telestai daemon running and synced
- [ ] Blockbook explorer accessible
- [ ] Nginx serving HTTPS correctly
- [ ] DNS pointing to Optimus
- [ ] All endpoints responding
- [ ] No errors in logs
- [ ] Old server can be safely stopped

---

## 📝 Next Steps

1. **Review this plan** and confirm approach
2. **Check Optimus resources** (disk space, memory)
3. **Schedule migration** (consider low-traffic time)
4. **Execute migration** following phases
5. **Monitor and verify** after completion

---

**Status:** ⏳ **Ready to execute when approved**


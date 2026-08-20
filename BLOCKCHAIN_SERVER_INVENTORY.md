# Blockchain Server Inventory - 45.32.67.179

**Date:** November 18, 2025  
**Server:** 45.32.67.179 (Vultr)  
**OS:** Ubuntu (Linux 5.4.0-216-generic)  
**Uptime:** 49 days, 22 hours

---

## 🔍 Server Overview

This is a **critical blockchain infrastructure server** running:
1. Telestai blockchain daemon (telestaid)
2. Blockbook blockchain explorer
3. Nginx reverse proxy with SSL

---

## 📦 Services Running

### 1. Telestai Blockchain Daemon (`backend-tls.service`)
**Status:** ✅ Active (running 49+ days)

**Details:**
- **Binary:** `/opt/coins/nodes/tls/bin/telestaid`
- **Configuration:** `/opt/coins/nodes/tls/tls.conf`
- **Data Directory:** `/opt/coins/data/tls/backend` (1.3GB)
- **RPC Port:** 8766 (localhost only)
- **P2P Port:** 28359 (localhost only)
- **User:** `tls`
- **PID:** 1069
- **Memory:** 81.2MB

**Process:**
```
/opt/coins/nodes/tls/bin/telestaid 
  -datadir=/opt/coins/data/tls/backend 
  -conf=/opt/coins/nodes/tls/tls.conf 
  -pid=/run/tls/tls.pid
```

**Data Contents:**
- `blocks/` - Blockchain blocks
- `chainstate/` - Chain state database
- `database/` - Additional database files
- `assets/` - Asset data
- `debug.log` - Debug log file

---

### 2. Blockbook Explorer (`blockbook-tls.service`)
**Status:** ✅ Active (running 19 hours, restarted recently)

**Details:**
- **Binary:** `/opt/coins/blockbook/tls/bin/blockbook`
- **Configuration:** `/opt/coins/blockbook/tls/config/blockchaincfg.json`
- **Data Directory:** `/opt/coins/data/tls/blockbook` (14GB)
- **Internal Port:** 8059
- **Public Port:** 8159
- **User:** `blockbook-tls`
- **PID:** 511043
- **Memory:** 7.0GB (high usage)
- **Certificate:** `/opt/coins/blockbook/tls/cert/blockbook`
- **Logs:** `/opt/coins/blockbook/tls/logs/`

**Process:**
```
/opt/coins/blockbook/tls/bin/blockbook 
  -blockchaincfg=/opt/coins/blockbook/tls/config/blockchaincfg.json 
  -datadir=/opt/coins/data/tls/blockbook/db 
  -sync 
  -internal=:8059 
  -public=:8159 
  -certfile=/opt/coins/blockbook/tls/cert/blockbook 
  -explorer= 
  -log_dir=/opt/coins/blockbook/tls/logs
```

**Note:** High memory usage (7GB) - ensure Optimus has sufficient RAM

---

### 3. Nginx Web Server
**Status:** ✅ Active

**Configuration:**
- **Site:** `blockbook.telestai.io`
- **Config:** `/etc/nginx/sites-available/blockbook`
- **SSL Certificate:** `/etc/letsencrypt/live/blockbook.telestai.io/`
- **Ports:** 80 (HTTP), 443 (HTTPS)

**Features:**
- HTTPS with Let's Encrypt certificate
- Rate limiting for `/spending/` endpoint (1 req/sec)
- CORS headers configured
- Proxy to blockbook on port 8159
- Long timeout settings (120s)

---

## 💾 Data Inventory

### Total Data Size: ~15.3GB

| Location | Size | Description |
|----------|------|-------------|
| `/opt/coins/data/tls/backend/` | 1.3GB | Telestai blockchain data |
| `/opt/coins/data/tls/blockbook/` | 14GB | Blockbook explorer database |
| `/opt/coins/nodes/tls/` | ~50MB | Telestai daemon binaries/config |
| `/opt/coins/blockbook/tls/` | ~100MB | Blockbook binaries/config |

### Configuration Files
- `/opt/coins/nodes/tls/tls.conf` - Telestai daemon config
- `/opt/coins/nodes/tls/tls_client.conf` - Client config
- `/opt/coins/blockbook/tls/config/blockchaincfg.json` - Blockbook config
- `/etc/systemd/system/backend-tls.service` - Systemd service
- `/etc/systemd/system/blockbook-tls.service` - Systemd service
- `/etc/nginx/sites-available/blockbook` - Nginx config
- `/etc/letsencrypt/live/blockbook.telestai.io/` - SSL certificates

---

## 🌐 Network Configuration

### Listening Ports
- **22** - SSH
- **80** - HTTP (nginx)
- **443** - HTTPS (nginx)
- **8766** - Telestai RPC (localhost only)
- **28359** - Telestai P2P (localhost only)
- **8059** - Blockbook internal (localhost only)
- **8159** - Blockbook public (localhost, proxied by nginx)

### Domain
- **blockbook.telestai.io** → Currently points to 45.32.67.179
- **SSL:** Let's Encrypt certificate installed

---

## 👥 Users and Permissions

### System Users
- **tls** - Runs telestaid daemon
- **blockbook-tls** - Runs blockbook explorer

### Directory Ownership
- `/opt/coins/nodes/tls/` → `tls:tls`
- `/opt/coins/data/tls/backend/` → `tls:tls`
- `/opt/coins/blockbook/tls/` → `blockbook-tls:blockbook-tls`
- `/opt/coins/data/tls/blockbook/` → `blockbook-tls:blockbook-tls`

---

## ⚠️ Critical Dependencies

1. **Blockbook depends on Telestai RPC**
   - Blockbook connects to telestaid on port 8766
   - Must start telestaid before blockbook
   - Blockbook syncs blockchain data from telestaid

2. **Service Startup Order**
   - 1. Start telestaid
   - 2. Wait for RPC to be available
   - 3. Start blockbook
   - 4. Start nginx

3. **Data Integrity**
   - Blockchain data must be copied completely
   - Blockbook database is large (14GB) - use rsync for resume
   - Verify data after copy

---

## 🔗 External Dependencies

### DNS
- `blockbook.telestai.io` must point to server IP
- Currently: 45.32.67.179
- After migration: 114.73.209.140

### SSL Certificates
- Let's Encrypt certificates are domain-based
- May need to re-issue if IP changes significantly
- Or copy existing certificates

---

## 📊 Resource Requirements

### Current Usage
- **CPU:** Moderate (load average: 4.11)
- **Memory:** ~7.1GB (mostly blockbook)
- **Disk:** 15.3GB data
- **Network:** Moderate

### Optimus Capacity
- **CPU:** Sufficient
- **Memory:** 31GB available ✅
- **Disk:** 1.7TB available ✅
- **Network:** Should be sufficient

---

## 🎯 Migration Considerations

### Critical Points
1. **Blockchain Sync Time**
   - Telestai daemon needs to sync to latest block
   - Time depends on blockchain height
   - May take 1-4 hours

2. **Blockbook Sync Time**
   - Blockbook needs to sync its database
   - 14GB database may take 1-2 hours
   - Depends on network and disk speed

3. **Service Dependencies**
   - Must maintain startup order
   - Blockbook cannot start without telestaid RPC

4. **DNS Propagation**
   - DNS change takes 5-10 minutes
   - Plan for brief downtime during switch

5. **SSL Certificates**
   - Certificates tied to domain
   - Should work after DNS update
   - May need to re-issue if issues occur

---

## ✅ Pre-Migration Checklist

- [x] Server inventory completed
- [x] Data sizes identified (15.3GB total)
- [x] Services identified and documented
- [x] Optimus resources verified (sufficient)
- [ ] Migration plan created
- [ ] Backup strategy confirmed
- [ ] DNS update plan ready
- [ ] Rollback plan prepared

---

**Status:** ✅ **Inventory Complete - Ready for Migration Planning**


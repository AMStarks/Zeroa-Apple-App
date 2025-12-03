# Port Forwarding Setup for SSL Certificate

## Current Status
- ✅ Cloudflare DNS: `halo.telestai.io` → `114.73.209.140` (DNS only, no proxy)
- ✅ Server ready: nginx configured, firewall allows 80/443
- ✅ Certbot installed and ready
- ⏳ **Waiting for:** Port forwarding configuration

## Port Forwarding Required

**You need to configure these port forwarding rules on your router:**

| External Port | Internal IP | Internal Port | Protocol | Purpose |
|--------------|-------------|---------------|----------|---------|
| 80 | 192.168.0.121 | 80 | TCP | HTTP (Let's Encrypt validation) |
| 443 | 192.168.0.121 | 443 | TCP | HTTPS (SSL/TLS) |

## Router Configuration Steps

1. **Access Router Admin Panel**
   - Usually: `http://192.168.0.1` or `http://192.168.1.1`
   - Or check router label for admin URL

2. **Navigate to Port Forwarding**
   - Look for: "Port Forwarding", "Virtual Server", "NAT", or "Firewall Rules"
   - Common locations: Advanced → Port Forwarding, or Network → NAT

3. **Add Port Forwarding Rules**

   **Rule 1: HTTP (Port 80)**
   - Name: `Halo HTTP`
   - External Port: `80`
   - Internal IP: `192.168.0.121`
   - Internal Port: `80`
   - Protocol: `TCP`
   - Enable: `Yes`

   **Rule 2: HTTPS (Port 443)**
   - Name: `Halo HTTPS`
   - External Port: `443`
   - Internal IP: `192.168.0.121`
   - Internal Port: `443`
   - Protocol: `TCP`
   - Enable: `Yes`

4. **Save and Apply**
   - Click "Save" or "Apply"
   - Wait for router to restart/apply changes (usually 30-60 seconds)

## Verification

**After setting up port forwarding, verify it works:**

```bash
# Test from external network (or use online tool like canyouseeme.org)
# Test HTTP
curl -I http://114.73.209.140/api/health

# Test HTTPS (after SSL is set up)
curl -I https://114.73.209.140/api/health
```

**Or use online port checker:**
- Visit: https://canyouseeme.org
- Test port 80: Should show "Success"
- Test port 443: Should show "Success" (after SSL setup)

## Once Port Forwarding is Configured

**SSH into Optimus and run:**

```bash
ssh -i ~/.ssh/id_optimus -p 2222 chief@114.73.209.140

# Then run:
sudo certbot --nginx -d halo.telestai.io \
    --non-interactive \
    --agree-tos \
    --email admin@telestai.io \
    --redirect
```

**Or use the setup script:**
```bash
bash setup_ssl_optimus.sh
```

## Expected Result

After port forwarding and SSL setup:
- ✅ `https://halo.telestai.io/api/health` returns healthy status
- ✅ iOS apps can connect via HTTPS
- ✅ Certificate auto-renews every 90 days

## Troubleshooting

**If port forwarding doesn't work:**
1. Verify router firewall isn't blocking
2. Check if ISP blocks ports 80/443 (some residential ISPs do)
3. Try using non-standard ports if blocked (requires Cloudflare configuration)
4. Verify internal IP hasn't changed (check DHCP reservation)

**If Let's Encrypt still fails:**
1. Wait 5-10 minutes after DNS change for full propagation
2. Verify DNS: `dig halo.telestai.io` should return `114.73.209.140`
3. Test direct access: `curl http://114.73.209.140/api/health`
4. Check router logs for blocked connections


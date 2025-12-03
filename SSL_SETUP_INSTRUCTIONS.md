# SSL/TLS Setup Instructions for Optimus

## ✅ Completed
- ✅ Cloudflare DNS updated: `halo.telestai.io` → `114.73.209.140`
- ✅ iOS apps updated to use `https://halo.telestai.io/api`
- ✅ ATS exceptions removed (no longer needed with HTTPS)

## 🔄 To Do (When Server is Accessible)

### 1. Port Forwarding (Router Configuration)

**Configure these port forwarding rules on your router:**

| External Port | Internal IP | Internal Port | Protocol | Description |
|--------------|-------------|---------------|----------|-------------|
| 80 | 192.168.0.121 | 80 | TCP | HTTP (for Let's Encrypt validation) |
| 443 | 192.168.0.121 | 443 | TCP | HTTPS |

**Steps:**
1. Log into your router admin panel
2. Navigate to Port Forwarding / Virtual Server settings
3. Add rule for port 80: `80 → 192.168.0.121:80`
4. Add rule for port 443: `443 → 192.168.0.121:443`
5. Save and apply changes

**Verify port forwarding:**
```bash
# From external network (or use online tool)
curl -I http://114.73.209.140/api/health
curl -I https://114.73.209.140/api/health
```

### 2. Run SSL Setup Script

**On Optimus server (192.168.0.121), run:**

```bash
# Copy the script to the server first, or run commands manually
bash setup_ssl_optimus.sh
```

**Or run manually:**

```bash
# Install certbot
sudo apt update
sudo apt install -y certbot python3-certbot-nginx

# Ensure nginx is configured for the domain
sudo tee /etc/nginx/sites-available/halo-api > /dev/null << 'EOF'
server {
    listen 80;
    server_name halo.telestai.io 192.168.0.121;

    location /api {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

sudo nginx -t
sudo systemctl reload nginx

# Obtain SSL certificate
sudo certbot --nginx -d halo.telestai.io \
    --non-interactive \
    --agree-tos \
    --email admin@telestai.io \
    --redirect

# Verify certificate
sudo certbot certificates

# Test auto-renewal
sudo certbot renew --dry-run
```

### 3. Update Firewall Rules

**Ensure UFW allows HTTP/HTTPS:**

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw status verbose
```

### 4. Verification Steps

**1. Test DNS resolution:**
```bash
dig halo.telestai.io
# Should return: 114.73.209.140
```

**2. Test HTTP (should redirect to HTTPS):**
```bash
curl -I http://halo.telestai.io/api/health
# Should return: 301 Moved Permanently
# Location: https://halo.telestai.io/api/health
```

**3. Test HTTPS:**
```bash
curl https://halo.telestai.io/api/health
# Should return: {"status":"healthy",...}
```

**4. Test SSL certificate:**
```bash
openssl s_client -connect halo.telestai.io:443 -servername halo.telestai.io < /dev/null
# Should show valid certificate from Let's Encrypt
```

**5. Test from iOS apps:**
- Rebuild apps in Xcode
- Test authentication flow
- Verify API calls work over HTTPS

## Troubleshooting

### Certificate Validation Fails
- **Issue:** Let's Encrypt can't validate domain
- **Solution:** 
  - Ensure port 80 is forwarded and accessible
  - Check nginx is running: `sudo systemctl status nginx`
  - Verify DNS propagation: `dig halo.telestai.io`
  - Check firewall: `sudo ufw status`

### Nginx Configuration Errors
- **Issue:** `nginx -t` fails
- **Solution:**
  - Check syntax: `sudo nginx -t`
  - Review config: `sudo cat /etc/nginx/sites-available/halo-api`
  - Check logs: `sudo tail -f /var/log/nginx/error.log`

### Port Forwarding Not Working
- **Issue:** External access fails
- **Solution:**
  - Verify router port forwarding rules
  - Test from external network
  - Check if ISP blocks ports 80/443
  - Consider using non-standard ports if blocked

## Notes

- **Certificate Auto-Renewal:** Certbot sets up automatic renewal (runs twice daily)
- **Certificate Location:** `/etc/letsencrypt/live/halo.telestai.io/`
- **Nginx Config:** Certbot automatically updates nginx config for HTTPS
- **Cloudflare Proxy:** If using Cloudflare proxy (orange cloud), SSL works end-to-end

## After Setup

Once SSL is working:
1. ✅ Apps are already updated to use `https://halo.telestai.io/api`
2. ✅ Rebuild apps in Xcode
3. ✅ Test authentication and API calls
4. ✅ Monitor certificate renewal (automatic)


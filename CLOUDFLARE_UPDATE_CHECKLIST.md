# Cloudflare DNS Update Checklist

## Current Status
- **Old Server:** 149.248.5.137 (Halo API Server)
- **New Server:** Optimus
  - **Local IP:** 192.168.0.121
  - **External IP:** 114.73.209.140
- **Domain:** halo.telestai.io
- **Apps Currently Using:** http://192.168.0.121/api (local IP)

## Cloudflare DNS Update Steps

### 1. Update DNS Record
**In Cloudflare Dashboard:**
- Go to DNS settings for `telestai.io`
- Find A record: `halo.telestai.io`
- Update IP from `149.248.5.137` → `114.73.209.140`
- TTL: Set to "Auto" or desired value
- Proxy status: Enable Cloudflare proxy (orange cloud) for DDoS protection

### 2. Port Forwarding (Router Configuration)
**Ensure these ports are forwarded on your router:**
- **Port 80 (HTTP):** External → 192.168.0.121:80
- **Port 443 (HTTPS):** External → 192.168.0.121:443
- **Port 22 (SSH):** Already configured (2222 → 22)

### 3. SSL/TLS Certificate Setup
**On Optimus server, install Let's Encrypt certificate:**

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Get certificate for halo.telestai.io
sudo certbot --nginx -d halo.telestai.io

# Auto-renewal is set up automatically
```

**Or use Cloudflare Origin Certificate:**
- Generate certificate in Cloudflare Dashboard
- Install on Optimus server
- Configure nginx to use it

### 4. Update Nginx Configuration
**Update `/etc/nginx/sites-available/halo-api` to handle HTTPS:**

```nginx
server {
    listen 80;
    server_name halo.telestai.io;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name halo.telestai.io;

    ssl_certificate /etc/letsencrypt/live/halo.telestai.io/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/halo.telestai.io/privkey.pem;
    
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
```

### 5. Update iOS Apps
**After SSL is set up, update apps back to use domain:**

**Zeroa (`HaloAPIService.swift`):**
```swift
private let baseURL = URL(string: "https://halo.telestai.io/api")!
```

**LASKO (`LASKOService.swift`):**
```swift
private let baseURL = "https://halo.telestai.io/api"
```

**Remove ATS exceptions** from Info.plist files (no longer needed with HTTPS)

### 6. Firewall Rules
**Ensure UFW allows HTTP/HTTPS:**
```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

### 7. Verification Steps
1. **DNS Propagation:**
   ```bash
   dig halo.telestai.io
   # Should return 114.73.209.140
   ```

2. **HTTP Redirect:**
   ```bash
   curl -I http://halo.telestai.io/api/health
   # Should redirect to HTTPS
   ```

3. **HTTPS Access:**
   ```bash
   curl https://halo.telestai.io/api/health
   # Should return healthy status
   ```

4. **Test from iOS Apps:**
   - Rebuild apps with updated URLs
   - Test authentication flow
   - Verify API calls work

## Timeline
- **DNS Update:** ~5 minutes (propagation can take up to 24 hours, usually much faster)
- **SSL Setup:** ~10 minutes
- **App Updates:** ~5 minutes
- **Testing:** ~15 minutes

## Rollback Plan
If issues occur:
1. Revert Cloudflare DNS to old IP (149.248.5.137)
2. Apps can temporarily use local IP (192.168.0.121)
3. Fix issues and try again

## Notes
- Cloudflare proxy (orange cloud) provides DDoS protection and caching
- SSL certificate auto-renews via certbot
- Consider setting up monitoring/alerting for the new server
- Update any other services that reference the old IP


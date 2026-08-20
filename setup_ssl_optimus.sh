#!/bin/bash
# SSL/TLS Setup Script for Optimus Server
# Run this on the Optimus server (192.168.0.121)

set -e

echo "=== Setting up SSL/TLS for halo.telestai.io ==="
echo ""

# Step 1: Install certbot
echo "Step 1: Installing certbot..."
sudo apt update
sudo apt install -y certbot python3-certbot-nginx

# Step 2: Ensure nginx is running and configured
echo ""
echo "Step 2: Checking nginx configuration..."
sudo nginx -t

# Step 3: Update nginx config to handle the domain properly
echo ""
echo "Step 3: Updating nginx configuration for domain..."
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

# Step 4: Obtain SSL certificate
echo ""
echo "Step 4: Obtaining Let's Encrypt certificate..."
echo "Note: This requires port 80 to be accessible from the internet"
echo "Make sure port forwarding is configured: 80→80 on your router"

sudo certbot --nginx -d halo.telestai.io \
    --non-interactive \
    --agree-tos \
    --email admin@telestai.io \
    --redirect

# Step 5: Verify certificate
echo ""
echo "Step 5: Verifying certificate..."
sudo certbot certificates

# Step 6: Test auto-renewal
echo ""
echo "Step 6: Testing certificate renewal..."
sudo certbot renew --dry-run

echo ""
echo "=== SSL/TLS Setup Complete ==="
echo ""
echo "Certificate location: /etc/letsencrypt/live/halo.telestai.io/"
echo "Auto-renewal: Configured (runs twice daily)"
echo ""
echo "Test HTTPS: curl https://halo.telestai.io/api/health"


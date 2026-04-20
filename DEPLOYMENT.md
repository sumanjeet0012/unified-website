# Deployment Guide: libp2p Unified Website on EC2

## Architecture

- **Zola Container**: Runs on-demand to build static HTML from Markdown
- **Nginx on Host**: Serves static files directly (no container needed for serving)
- **Volume Mapping**: `/home/ubuntu/unified-website` on host ↔ `/project` in container

```
[Zola Container]  →  builds public/ folder  →  [Nginx on Host]  →  serves to users
```

---

## Prerequisites

- AWS account with EC2 access
- A domain name pointing to your EC2 IP (e.g., DuckDNS, Route53)
- SSH key pair for EC2 access

---

## EC2 Setup

### Step 1: Launch EC2 Instance

1. Go to AWS Console → EC2 → Launch Instance
2. Choose **Ubuntu 22.04 LTS** (free tier eligible)
3. Instance type: **t3.micro** (free tier) or larger
4. Configure Security Group — open these ports:
   - **22** (SSH)
   - **80** (HTTP)
   - **443** (HTTPS)
5. Download your `.pem` key file

### Step 2: SSH into EC2

```bash
chmod 400 your-key.pem
ssh -i your-key.pem ubuntu@<EC2_PUBLIC_IP>
```

### Step 3: Install Docker & Nginx

```bash
# Update system packages
sudo apt-get update -y

# Install Docker
sudo apt-get install docker.io -y
sudo systemctl start docker
sudo systemctl enable docker

# Allow ubuntu user to run Docker without sudo
sudo usermod -aG docker ubuntu

# Install Nginx
sudo apt-get install nginx -y
sudo systemctl start nginx
sudo systemctl enable nginx

# IMPORTANT: Exit and SSH back in for Docker group permissions to take effect
exit
ssh -i your-key.pem ubuntu@<EC2_PUBLIC_IP>
```

Verify both services are running:

```bash
sudo systemctl status docker
sudo systemctl status nginx
```

### Step 4: Clone Repository

```bash
cd ~
git clone https://github.com/libp2p/unified-website.git
cd unified-website
```

### Step 5: Build Static Files with Zola

```bash
# Pull the Zola Docker image and build the site
# -v maps host folder to /project inside container
# Zola outputs to /project/public = /home/ubuntu/unified-website/public on host

docker run --rm \
  -v /home/ubuntu/unified-website:/project \
  ghcr.io/getzola/zola:v0.22.1 \
  zola build
```

Expected output:
```
Building site...
-> Creating 181 pages (0 orphan) and 15 sections
Done in 7.7s.
```

Verify the build:

```bash
ls -la /home/ubuntu/unified-website/public/
# Should show: blog/, docs/, img/, fonts/, js/, css/, index.html, etc.
```

> **Note**: The `public/` folder is completely regenerated on every build (old files are overwritten).

### Step 6: Fix File Permissions (CRITICAL)

This is the **most important step** and the source of most 403/404 errors.

Nginx runs as `www-data` user. The Docker container creates files owned by `root`. Nginx cannot read files it does not own or have permission to access.

```bash
# Change ownership of all files to www-data (Nginx user)
sudo chown -R www-data:www-data /home/ubuntu/unified-website/

# Set correct permissions:
# 755 on directories = allows Nginx to traverse/list them
# 644 on files = allows Nginx to read them
sudo find /home/ubuntu/unified-website/public -type d -exec chmod 755 {} \;
sudo find /home/ubuntu/unified-website/public -type f -exec chmod 644 {} \;

# Verify
ls -la /home/ubuntu/unified-website/public/img/ | head -5
```

> ⚠️ **You must run the permission fix after EVERY build.** Each Docker run creates new files with wrong ownership.

### Step 7: Configure Nginx

Edit Nginx config:

```bash
sudo nano /etc/nginx/sites-available/default
```

Replace entire file with:

```nginx
server {
    listen 80;
    server_name sumanjeet.duckdns.org;  # Replace with your domain

    root /home/ubuntu/unified-website/public;
    index index.html;

    # Handle clean URLs (Zola generates /blog/index.html for /blog/)
    location / {
        try_files $uri $uri/ $uri.html =404;
    }

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_types text/plain text/css application/javascript application/json image/svg+xml;
    gzip_min_length 1000;

    # Cache static assets for 1 year
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2|woff|ttf)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

> ⚠️ **Important**: `server_name` must be set to your actual domain, NOT `_`. Certbot needs this to install SSL certificates later.

Test and apply config:

```bash
sudo systemctl restart nginx
```

### Step 8: Test HTTP

```bash
# Test from EC2 itself
curl http://localhost/
curl http://localhost/blog/
curl http://localhost/docs/
```

### Step 9: Setup HTTPS with Let's Encrypt

#### Install Certbot

```bash
sudo apt-get install certbot python3-certbot-nginx -y
```

#### Get and Install Certificate

```bash
sudo certbot --nginx -d sumanjeet.duckdns.org
```

When prompted, select **option 1** to install the existing certificate (if already obtained). Certbot automatically updates your Nginx config to add SSL.

Expected output:
```
Successfully deployed certificate for sumanjeet.duckdns.org to /etc/nginx/sites-enabled/default
Congratulations! You have successfully enabled HTTPS on https://sumanjeet.duckdns.org
```

#### Verify HTTPS

```bash
curl https://sumanjeet.duckdns.org/
curl -I https://sumanjeet.duckdns.org/img/logo_small.png  # Should be 200 OK

# Check certificate details
sudo certbot certificates

# Test auto-renewal (dry run)
sudo certbot renew --dry-run
```

> **Note**: HTTP (port 80) automatically redirects to HTTPS (port 443) after Certbot runs.

### Step 10: Final Verification

```bash
# 1. Homepage
curl -I https://sumanjeet.duckdns.org/

# 2. Blog section
curl -I https://sumanjeet.duckdns.org/blog/

# 3. Docs section
curl -I https://sumanjeet.duckdns.org/docs/

# 4. Static assets (images, fonts)
curl -I https://sumanjeet.duckdns.org/img/logo_small.png
curl -I https://sumanjeet.duckdns.org/fonts/google/inter-latin.woff2

# All should return: HTTP/2 200
```

---

## Updating the Site

When you push new content or changes:

```bash
cd /home/ubuntu/unified-website

# 1. Pull latest code
git pull origin main

# 2. Rebuild with Zola
docker run --rm \
  -v /home/ubuntu/unified-website:/project \
  ghcr.io/getzola/zola:v0.22.1 \
  zola build

# 3. Fix permissions (ALWAYS do this after build!)
sudo chown -R www-data:www-data /home/ubuntu/unified-website/
sudo find /home/ubuntu/unified-website/public -type d -exec chmod 755 {} \;
sudo find /home/ubuntu/unified-website/public -type f -exec chmod 644 {} \;

# 4. Restart Nginx
sudo systemctl restart nginx

# 5. Verify
curl https://sumanjeet.duckdns.org/
```

---

## Automation Script

Save this as `/home/ubuntu/deploy.sh` to automate future updates:

```bash
#!/bin/bash
set -e

echo "Starting deployment..."

cd /home/ubuntu/unified-website

echo "Pulling latest changes..."
git pull origin main

echo "Building site with Zola..."
docker run --rm \
  -v /home/ubuntu/unified-website:/project \
  ghcr.io/getzola/zola:v0.22.1 \
  zola build

echo "Fixing permissions..."
sudo chown -R www-data:www-data /home/ubuntu/unified-website/
sudo find /home/ubuntu/unified-website/public -type d -exec chmod 755 {} \;
sudo find /home/ubuntu/unified-website/public -type f -exec chmod 644 {} \;

echo "Restarting Nginx..."
sudo systemctl restart nginx

echo "Deployment complete!"
curl -s -o /dev/null -w "Site status: %{http_code}\n" https://sumanjeet.duckdns.org/
```

Make it executable and run:

```bash
chmod +x /home/ubuntu/deploy.sh
./deploy.sh
```

---

## Monitoring

```bash
# Check Nginx status
sudo systemctl status nginx

# Watch access logs live
sudo tail -f /var/log/nginx/access.log

# Watch error logs live
sudo tail -f /var/log/nginx/error.log

# Check last 20 error log entries
sudo tail -20 /var/log/nginx/error.log

# Check disk usage of built files
du -sh /home/ubuntu/unified-website/public/

# Check certificate expiry
sudo certbot certificates
```

---

## File Locations

| Resource | Path |
|---|---|
| Project root | `/home/ubuntu/unified-website/` |
| Built static files | `/home/ubuntu/unified-website/public/` |
| Nginx config | `/etc/nginx/sites-available/default` |
| Nginx enabled config | `/etc/nginx/sites-enabled/default` |
| SSL certificate | `/etc/letsencrypt/live/sumanjeet.duckdns.org/fullchain.pem` |
| SSL private key | `/etc/letsencrypt/live/sumanjeet.duckdns.org/privkey.pem` |
| Nginx access logs | `/var/log/nginx/access.log` |
| Nginx error logs | `/var/log/nginx/error.log` |
| Deployment script | `/home/ubuntu/deploy.sh` |

---

## Troubleshooting

### Homepage works but /blog or /docs return 404

**Cause**: Permissions are wrong on subdirectories after Docker build.

**Fix**:
```bash
# 1. Verify the folders were built
ls -la /home/ubuntu/unified-website/public/blog/
ls -la /home/ubuntu/unified-website/public/docs/

# 2. Fix permissions
sudo chown -R www-data:www-data /home/ubuntu/unified-website/
sudo find /home/ubuntu/unified-website/public -type d -exec chmod 755 {} \;
sudo find /home/ubuntu/unified-website/public -type f -exec chmod 644 {} \;

# 3. Restart Nginx
sudo systemctl restart nginx

# 4. Test
curl https://sumanjeet.duckdns.org/blog/
```

---

### 403 Forbidden on images, fonts, or CSS

**Cause**: Docker creates files owned by `root`. Nginx (www-data) cannot read them.

**Symptoms in browser console**:
```
GET https://sumanjeet.duckdns.org/img/logo_small.png 403 (Forbidden)
GET https://sumanjeet.duckdns.org/fonts/google/inter-latin.woff2 403 (Forbidden)
GET https://sumanjeet.duckdns.org/js/common.js 403 (Forbidden)
```

**Fix**:
```bash
sudo chown -R www-data:www-data /home/ubuntu/unified-website/
sudo find /home/ubuntu/unified-website/public -type d -exec chmod 755 {} \;
sudo find /home/ubuntu/unified-website/public -type f -exec chmod 644 {} \;
sudo systemctl restart nginx

# Verify
curl -I https://sumanjeet.duckdns.org/img/logo_small.png  # Must be 200
```

---

### 403 on root (stat failed: Permission denied)

**Cause**: Nginx cannot traverse the parent directory to reach `public/`.

**Symptoms in error log**:
```
stat() "/home/ubuntu/unified-website/public/" failed (13: Permission denied)
```

**Fix**:
```bash
# Parent directories also need 755
sudo chmod 755 /home/ubuntu
sudo chmod 755 /home/ubuntu/unified-website
sudo chmod 755 /home/ubuntu/unified-website/public
sudo systemctl restart nginx
```

---

### Certbot: "Could not find matching server block"

**Error**:
```
Could not automatically find a matching server block for sumanjeet.duckdns.org.
Set the `server_name` directive to use the Nginx installer.
```

**Cause**: Nginx config has `server_name _;` instead of actual domain.

**Fix**:
```bash
sudo nano /etc/nginx/sites-available/default

# Change:  server_name _;
# To:      server_name sumanjeet.duckdns.org;

sudo nginx -t
sudo systemctl reload nginx

# Run Certbot again
sudo certbot --nginx -d sumanjeet.duckdns.org
# Select option 1 to reinstall existing certificate
```

---

### Port 80 already in use

```bash
sudo killall nginx
sudo systemctl restart nginx
```

---

### Zola build fails

```bash
# Run with verbose output to see errors
docker run --rm \
  -v /home/ubuntu/unified-website:/project \
  ghcr.io/getzola/zola:v0.22.1 \
  zola build

# Check config.toml for syntax errors
cat /home/ubuntu/unified-website/config.toml
```

---

### Browser console: "SES Removing unpermitted intrinsics"

**Status**: Harmless, not an error.

This is the Secure ECMAScript (SES) security library intentionally restricting JavaScript features. Normal security behavior. No action needed.

---

### Browser console: Sentry POST 403 Forbidden

**Status**: Harmless, not critical.

Sentry is a third-party error tracking service. The 403 means your browser is blocking the request due to CORS policy. Your site works perfectly without it. No action needed.

---

## Costs

| Resource | Cost |
|---|---|
| t3.micro EC2 | ~$0.01/hour (~$8/month, free tier eligible) |
| Data transfer | First 100GB/month free |
| SSL Certificate | Free (Let's Encrypt) |
| DuckDNS domain | Free |
| **Total** | **< $10/month** |

---

## Key Lessons Learned

1. **Permissions after every build** — Docker creates files as `root`. Nginx runs as `www-data`. Always `chown` + `chmod` after every `zola build`.

2. **`server_name` must be set before Certbot** — Certbot looks for a matching server block with your domain. `server_name _;` will not work.

3. **Use full paths in Docker volume mounts** — Use `/home/ubuntu/unified-website` not `~/unified-website` to avoid path resolution issues.

4. **Parent directory permissions matter** — Nginx needs `755` on `/home/ubuntu` and `/home/ubuntu/unified-website` to traverse the path to `public/`.

5. **All sections need to be built** — If `/blog/` or `/docs/` return 404, check that `public/blog/` and `public/docs/` exist after the Zola build.

6. **Browser console warnings are not always errors** — SES and Sentry warnings are normal and do not affect functionality.


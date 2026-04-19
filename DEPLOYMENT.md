# Deployment Guide: Zola Site to EC2

## Architecture

- **Zola Container**: Builds static files (runs on-demand)
- **Nginx on Host**: Serves static files directly
- **Volume Mapping**: Project folder shared between host and container

---

## EC2 Setup

### Step 1: Launch EC2 & SSH

```bash
ssh -i your-key.pem ubuntu@<EC2_PUBLIC_IP>
```

### Step 2: Install Docker & Nginx

```bash
# Update system
sudo apt-get update -y

# Install Docker
sudo apt-get install docker.io -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ubuntu

# Install Nginx
sudo apt-get install nginx -y
sudo systemctl start nginx
sudo systemctl enable nginx

# Exit and SSH back in (for docker group permissions)
exit
ssh -i your-key.pem ubuntu@<EC2_PUBLIC_IP>
```

### Step 3: Clone Repository

```bash
cd ~
git clone https://github.com/libp2p/unified-website.git
cd unified-website
```

### Step 4: Build Static Files

```bash
# Run Zola container with volume mapping
# Container builds files → /project/public
# Host sees files at → ~/unified-website/public

docker run --rm -v /home/ubuntu/unified-website:/project ghcr.io/getzola/zola:v0.22.1 zola build

# Verify files were built
ls -la public/

# Set correct permissions for Nginx to read them
sudo chmod 755 /home/ubuntu/unified-website
sudo chmod 755 /home/ubuntu/unified-website/public
sudo chmod -R 644 /home/ubuntu/unified-website/public/*
sudo chmod -R 755 /home/ubuntu/unified-website/public/*/
```

### Step 5: Configure Nginx

Edit Nginx config:

```bash
sudo nano /etc/nginx/sites-available/default
```

Replace entire file with:

```nginx
server {
    listen 80;
    server_name sumanjeet.duckdns.org;  # Replace with your domain

    # Point to the Zola build output folder
    root /home/ubuntu/unified-website/public;
    index index.html;

    location / {
        try_files $uri $uri/ $uri.html =404;
    }

    # Compression
    gzip on;
    gzip_vary on;
    gzip_types text/plain text/css application/javascript application/json image/svg+xml;
    gzip_min_length 1000;

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2|woff|ttf)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

Restart Nginx:

```bash
sudo systemctl restart nginx
```

### Step 6: Test

```bash
# Test locally
curl http://localhost/

# Or visit in browser
# http://<EC2_PUBLIC_IP>
```

---

## Update Content

When you update the site with new blog posts, docs, or content:

```bash
cd ~/unified-website

# Pull latest changes
git pull origin main

# Rebuild static files with Zola container
docker run --rm -v /home/ubuntu/unified-website:/project ghcr.io/getzola/zola:v0.22.1 zola build

# Fix permissions on generated files (IMPORTANT!)
sudo chown -R www-data:www-data /home/ubuntu/unified-website/
sudo find /home/ubuntu/unified-website/public -type d -exec chmod 755 {} \;
sudo find /home/ubuntu/unified-website/public -type f -exec chmod 644 {} \;

# Restart Nginx to serve new files
sudo systemctl restart nginx

# Test
curl https://sumanjeet.duckdns.org/
```

**Note**: Permission fixing is **critical** after every build. New files are created by the Docker container and may have incorrect permissions.

---

## Setup HTTPS (Let's Encrypt)

### Step 1: Update Nginx config with domain

```bash
sudo nano /etc/nginx/sites-available/default
```

Change `server_name _;` to `server_name yourdomain.com;` (e.g., `sumanjeet.duckdns.org`)

```bash
sudo nginx -t
sudo systemctl reload nginx
```

### Step 2: Get and install certificate

```bash
# Install Certbot
sudo apt-get install certbot python3-certbot-nginx -y

# Get and install certificate
sudo certbot --nginx -d yourdomain.com

# When prompted, select option 1 to reinstall existing cert
# Certbot will automatically update Nginx config with SSL
```

### Step 3: Verify HTTPS works

```bash
# Test from EC2
curl https://yourdomain.com/

# Visit in browser
# https://sumanjeet.duckdns.org (or your domain)

# Check certificate details
sudo certbot certificates

# Test auto-renewal
sudo certbot renew --dry-run
```

**Note**: HTTP (port 80) will automatically redirect to HTTPS (port 443)

---

## Complete Deployment Checklist

After initial setup, verify everything works:

```bash
# 1. Verify Zola build
docker run --rm -v /home/ubuntu/unified-website:/project ghcr.io/getzola/zola:v0.22.1 zola build

# 2. Fix permissions (CRITICAL - do this after every build!)
sudo chown -R www-data:www-data /home/ubuntu/unified-website/
sudo find /home/ubuntu/unified-website/public -type d -exec chmod 755 {} \;
sudo find /home/ubuntu/unified-website/public -type f -exec chmod 644 {} \;

# 3. Restart Nginx
sudo systemctl restart nginx

# 4. Test HTTP
curl http://sumanjeet.duckdns.org/

# 5. Test HTTPS
curl https://sumanjeet.duckdns.org/

# 6. Check certificate
sudo certbot certificates

# 7. Verify files accessible
curl -I https://sumanjeet.duckdns.org/img/logo_small.png  # Should be 200 OK
```

---

## Monitoring

```bash
# Check Nginx status
sudo systemctl status nginx

# View Nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# Check disk usage
du -sh ~/unified-website/public/
```

---

## Troubleshooting

### Site returns 404 or Permission denied

**Error**: `Permission denied` in `/var/log/nginx/error.log` or site shows 404

**Root Cause**: Nginx (www-data user) cannot read files or traverse directories

**Solution**:

```bash
# Step 1: Change ownership to www-data (Nginx user)
sudo chown -R www-data:www-data /home/ubuntu/unified-website/

# Step 2: Set correct permissions
# 755 for directories (rwx r-x r-x)
# 644 for files (rw- r-- r--)
sudo find /home/ubuntu/unified-website/public -type d -exec chmod 755 {} \;
sudo find /home/ubuntu/unified-website/public -type f -exec chmod 644 {} \;

# Step 3: Restart Nginx
sudo systemctl restart nginx

# Step 4: Verify
curl http://localhost/
```

**Why this works**:
- `www-data` = User that Nginx runs as
- `755` on directories = Allows Nginx to list & traverse
- `644` on files = Allows Nginx to read files
- Parent directories also need `755` for path traversal

### Images return 403 Forbidden on HTTPS

**Error**: Browser console shows `GET https://yourdomain.com/img/logo.png 403 (Forbidden)`

**Root Cause**: File permissions are too restrictive or ownership is wrong

**Solution**:

```bash
# Reset ownership to www-data
sudo chown -R www-data:www-data /home/ubuntu/unified-website/

# Fix all file and directory permissions
sudo find /home/ubuntu/unified-website/public -type d -exec chmod 755 {} \;
sudo find /home/ubuntu/unified-website/public -type f -exec chmod 644 {} \;

# Verify images are readable
ls -la /home/ubuntu/unified-website/public/img/ | head -5

# Restart Nginx
sudo systemctl restart nginx
```

**Test**:
```bash
# Check if files are accessible
curl -I https://sumanjeet.duckdns.org/img/logo_small.png
# Should return 200 OK, not 403
```

### Mixed content warning (HTTP on HTTPS site)

**Error**: `Mixed Content: The page was loaded over HTTPS, but requested an insecure resource`

**Root Cause**: `config.toml` has `base_url = "http://..."` instead of HTTPS

**Solution**:

```bash
# Edit config
cd ~/unified-website
nano config.toml

# Change this line:
# base_url = "http://sumanjeet.duckdns.org"

# To this:
# base_url = "https://sumanjeet.duckdns.org"

# Rebuild
docker run --rm -v /home/ubuntu/unified-website:/project ghcr.io/getzola/zola:v0.22.1 zola build

# Restart Nginx
sudo systemctl restart nginx
```

### Certbot can't find server block

**Error**: `Could not automatically find a matching server block for yourdomain.com`

**Root Cause**: Nginx config has `server_name _;` instead of your domain

**Solution**:

```bash
# Edit Nginx config
sudo nano /etc/nginx/sites-available/default

# Change this line:
# server_name _;

# To this:
# server_name sumanjeet.duckdns.org;

# Test config
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx

# Now try Certbot again
sudo certbot --nginx -d sumanjeet.duckdns.org
```

### Port 80 already in use

```bash
# Kill existing Nginx process
sudo killall nginx
sudo systemctl restart nginx
```

### Browser console shows "SES Removing unpermitted intrinsics"

**Status**: ✅ **Harmless - Not an error**

- `SES` = Secure ECMAScript (security library)
- This is an intentional security warning, not a problem
- No action needed

### Browser console shows Sentry POST 403 Forbidden

**Status**: ✅ **Harmless - Not critical**

- Sentry = Third-party error tracking service
- The 403 means your browser is blocking the POST request (CORS policy)
- This is normal and your site works fine without Sentry
- You can safely ignore these warnings

**If you want to remove Sentry errors**, you'd need to:
1. Remove Sentry SDK from your HTML/templates
2. Or configure CORS to allow Sentry requests
3. Or disable Sentry in your site configuration

### Site not loading

```bash
# Check Nginx is running
sudo systemctl status nginx

# Check config syntax
sudo nginx -t

# Check files exist
ls -la ~/unified-website/public/
```

### Zola build failed

```bash
# Check build logs
docker run --rm -v /home/ubuntu/unified-website:/project ghcr.io/getzola/zola:v0.22.1 zola build

# Check for errors in config.toml
cat config.toml
```

### Permission issues

**Common symptoms:**
- Site returns 404 despite files existing
- Browser shows 403 Forbidden for images/fonts/CSS
- Error log shows: `stat() failed (13: Permission denied)`

**Complete permission fix**:

```bash
# Reset ownership to Nginx user
sudo chown -R www-data:www-data /home/ubuntu/unified-website/

# Directories need 755 (rwx r-x r-x)
sudo find /home/ubuntu/unified-website/public -type d -exec chmod 755 {} \;

# Files need 644 (rw- r-- r--)
sudo find /home/ubuntu/unified-website/public -type f -exec chmod 644 {} \;

# Verify
ls -la /home/ubuntu/unified-website/public/img/ | head -3
sudo systemctl restart nginx
curl https://sumanjeet.duckdns.org/
```

**Why permissions matter**:
- `www-data` = User running Nginx (needs to own files)
- `755` on dirs = Allows traversal (execute bit needed)
- `644` on files = Allows reading (read bits needed)

---

## File Locations

- **Project**: `/home/ubuntu/unified-website/`
- **Built files**: `/home/ubuntu/unified-website/public/`
- **Nginx config**: `/etc/nginx/sites-available/default`
- **Nginx logs**: `/var/log/nginx/`

---

## Costs

- **t3.micro** EC2: ~$0.01/hour (free tier eligible)
- **Data transfer**: First 100GB/month free
- **SSL Certificate**: Free (Let's Encrypt)
- **Total**: < $5/month

---

## Lessons Learned & Best Practices

### 1. **Permissions are Critical**
- Always set `www-data:www-data` ownership for files served by Nginx
- Directories need `755` (rwx for owner, rx for group/others)
- Files need `644` (rw for owner, r for group/others)
- Do this **after every Docker build**

### 2. **HTTPS Configuration**
- Set `server_name` in Nginx config **before** running Certbot
- Update `config.toml` to use `https://` base URL
- Certbot handles auto-renewal automatically in background

### 3. **Volume Mapping**
- Use full paths like `/home/ubuntu/unified-website` instead of `~/unified-website` in Docker commands
- Container outputs to `/project/public`, accessible at `/home/ubuntu/unified-website/public` on host

### 4. **Browser Console Warnings**
- "SES Removing unpermitted intrinsics" = Normal security behavior, not an error
- Sentry 403 errors = Normal when CORS blocks third-party requests, not critical
- These don't affect site functionality

### 5. **Update Workflow**
- `git pull` → `docker run zola build` → Fix permissions → `nginx restart`
- Automate with a shell script to avoid forgetting permission fixes

### 6. **Monitoring**
```bash
# Keep these handy:
sudo systemctl status nginx          # Check if running
sudo nginx -t                        # Validate config
sudo tail -20 /var/log/nginx/error.log  # Debug issues
curl -I https://yourdomain.com      # Test site
```

---

## Automation (Optional)

Create a deployment script to automate everything:

```bash
#!/bin/bash
# deploy.sh

cd /home/ubuntu/unified-website

# Pull latest
git pull origin main || exit 1

# Build
docker run --rm -v /home/ubuntu/unified-website:/project ghcr.io/getzola/zola:v0.22.1 zola build || exit 1

# Fix permissions
sudo chown -R www-data:www-data /home/ubuntu/unified-website/
sudo find /home/ubuntu/unified-website/public -type d -exec chmod 755 {} \;
sudo find /home/ubuntu/unified-website/public -type f -exec chmod 644 {} \;

# Restart
sudo systemctl restart nginx

echo "✅ Deployment complete!"
curl https://sumanjeet.duckdns.org/ > /dev/null && echo "✅ Site is live!"
```

Run with: `./deploy.sh`

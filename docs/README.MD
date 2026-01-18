# ESC Django Application - Production Deployment Guide

Complete guide for deploying the ESC Django application on a VPS with Docker, Nginx, Cloudflare, and enterprise-grade security hardening.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Installation](#detailed-installation)
- [Security Hardening](#security-hardening)
- [Configuration](#configuration)
- [Cloudflare Setup](#cloudflare-setup)
- [Management](#management)
- [Troubleshooting](#troubleshooting)
- [Security Best Practices](#security-best-practices)
- [Backup and Restore](#backup-and-restore)
- [Updates and Maintenance](#updates-and-maintenance)
- [Performance Tuning](#performance-tuning)
- [Support](#support)
- [License](#license)

## Overview

This deployment setup provides a **production-ready environment** for the ESC Django application with:

- **Docker Compose** for container orchestration
- **Nginx** as reverse proxy with Cloudflare-only enforcement
- **Redis** for caching and message broker
- **Celery** for async task processing
- **Celery Beat** for scheduled tasks
- **Cloudflare** for SSL, CDN, and DDoS protection
- **🛡️ Fail2Ban** for enterprise-grade threat detection and response
- **🔒 Multi-layer Rate Limiting** to prevent brute force and DoS attacks
- **🚨 Vulnerability Scanner Detection** with automatic permanent bans
- **⚡ SQL Injection/XSS Protection** with zero-tolerance policies

## Architecture

```
Internet
    ↓
Cloudflare (SSL, CDN, DDoS Protection, WAF)
    ↓
Fail2Ban (Threat Detection & IP Banning)
    ↓
Nginx (Port 80/443, Cloudflare-only enforcement, Rate Limiting)
    ↓
Django App (Port 8000)
    ↓
┌───────┴──────────────┐
↓                      ↓
Celery Worker      Celery Beat
↓                      ↓
└───────┬──────────────┘
        ↓
    Redis (Cache/Broker)
```

## Prerequisites

### Server Requirements

- **OS**: Ubuntu 20.04+ or Debian 11+
- **RAM**: Minimum 2GB (4GB recommended)
- **CPU**: 2+ cores recommended
- **Storage**: 20GB+ free space
- **User**: Non-root user with sudo privileges

### External Requirements

- Domain name pointed to your VPS
- Cloudflare account (free tier works)
- Docker Hub account (for pulling private images)
- SSH access to your VPS
- (Optional) Email account for security alerts

### Domain Configuration

Before starting, ensure your domain's DNS is configured:

1. Add an **A record** pointing to your VPS IP address
2. Configure through Cloudflare (recommended) or your domain registrar
3. Wait for DNS propagation (can take up to 24 hours, usually much faster)

## Quick Start

For experienced users, here's the fastest way to deploy:

```bash
# 1. SSH into your VPS
ssh user@your-server-ip

# 2. Download and run the deployment script
curl -fsSL https://raw.githubusercontent.com/andreas-tuko/esc-compose-prod/main/deploy.sh -o deploy.sh
chmod +x deploy.sh
./deploy.sh

# 3. Follow the interactive prompts
# The script will ask for:
# - Domain name
# - Docker Hub credentials
# - Security preferences (Recommended: Enable all)
# - Admin email for security alerts

# 4. Configure your environment
nano /opt/apps/esc/.env.docker

# 5. Verify security setup
/opt/bin/f2b-dashboard.sh

# 6. Your secure application is running!
```

**That's it!** Your application is now running with enterprise-grade security.

## Detailed Installation

### Step 1: Prepare Your VPS

Connect to your VPS via SSH:

```bash
ssh user@your-server-ip
```

If this is a fresh server, update the system:

```bash
sudo apt update && sudo apt upgrade -y
```

### Step 2: Download the Deployment Script

```bash
# Download the script
curl -fsSL https://raw.githubusercontent.com/andreas-tuko/esc-compose-prod/main/deploy.sh -o deploy.sh

# Make it executable
chmod +x deploy.sh
```

### Step 3: Run the Installation Script

```bash
./deploy.sh
```

The script will guide you through an interactive setup. Here's what it will ask:

#### Configuration Prompts

1. **Domain Name**: Enter your full domain (e.g., `example.com`)
   - Don't include `http://` or `https://`
   - Can include `www` if you prefer

2. **Docker Hub Credentials**:
   - Username: Your Docker Hub username
   - Password/Token: Your Docker Hub password or access token

3. **Application Directory**: Default is `/opt/apps/esc`
   - Press Enter to accept default
   - Or specify a custom path

4. **Create Deployer User**: Recommended for security
   - Creates a dedicated `deployer` user
   - Isolates application from main user

5. **Configure Firewall**: Recommended for security
   - Sets up UFW firewall
   - Opens only necessary ports (22, 80, 443)

6. **SSL Certificate Setup**: Choose your SSL option
   - **Let's Encrypt**: Free, trusted, auto-renewing (requires domain)
   - **Self-Signed**: Works with IP addresses (shows browser warning)
   - **None**: Use Cloudflare SSL only (HTTP to server)
   - See [SSL.md](docs/SSL.md) for detailed SSL guide

7. **🛡️ Security Features** (NEW): Enable enterprise-grade protection
   - **Recommended**: Choose **Yes** (enabled by default)
   - Includes Fail2Ban, rate limiting, vulnerability detection

8. **Admin Email for Security Alerts**:
   - Email for ban notifications and security alerts
   - Leave blank to disable email alerts (still logs all bans)

9. **Environment Configuration**: **Interactive editor opens automatically**
   - SECRET_KEY is auto-generated ✓
   - Domain is pre-configured ✓
   - You configure: Email, Database, and optional services
   - Built-in validation ensures correct configuration
   - See [CONFIGURATION.md](docs/CONFIGURATION.md) for detailed guide

#### What the Script Does

The installation script automatically:

1. ✅ Updates system packages
2. ✅ Installs Docker and Docker Compose
3. ✅ Creates application directory
4. ✅ Clones the repository from GitHub
5. ✅ Logs into Docker Hub
6. ✅ Creates environment configuration file with auto-generated SECRET_KEY
7. ✅ Opens interactive editor for you to configure required settings
8. ✅ Validates configuration before proceeding
9. ✅ 🛡️ **Installs and configures Fail2Ban** (NEW)
   - 10 specialized threat detection jails
   - Custom security filters
   - Automatic IP banning
   - Custom logging and reporting
10. ✅ **Installs and configures secure Nginx**
   - Cloudflare-only IP enforcement
   - Catch-all server blocks non-Cloudflare traffic
   - Multi-layer rate limiting
   - Security headers
11. ✅ Sets up systemd service for auto-start
12. ✅ Configures firewall (if selected)
13. ✅ **Creates security management scripts** (NEW)
   - Security dashboard
   - Manual unban tool
   - Monitoring utilities
14. ✅ Pulls Docker images and starts services

**Key Feature**: The script includes an interactive configuration editor that:
- Auto-generates secure SECRET_KEY
- Pre-fills your domain
- Guides you through required vs optional settings
- Validates configuration before starting
- Prevents common configuration mistakes

### Step 4: Configuration (Automatic Interactive Process)

The script will automatically open a nano editor with your environment configuration.

**What's Already Configured:**
- ✅ SECRET_KEY (auto-generated, secure)
- ✅ ALLOWED_HOSTS (your domain)
- ✅ SITE_URL (your domain)
- ✅ Sensible defaults for all settings

**What You Need to Configure:**

**Required for core functionality:**
```bash
# Email settings (for sending emails)
EMAIL_HOST_USER=your-email@gmail.com
EMAIL_HOST_PASSWORD=your-gmail-app-password

# Database (only if using PostgreSQL)
DATABASE_URL=postgresql://user:password@host:5432/dbname
```

**Optional (configure if using these features):**
```bash
# Cloudflare R2 (for file storage)
CLOUDFLARE_R2_ACCESS_KEY=your-key
CLOUDFLARE_R2_SECRET_KEY=your-secret

# M-Pesa (for payments in Kenya)
MPESA_CONSUMER_KEY=your-key
MPESA_CONSUMER_SECRET=your-secret

# Google OAuth (for social login)
GOOGLE_OAUTH_CLIENT_ID=your-client-id
GOOGLE_OAUTH_CLIENT_SECRET=your-secret

# Monitoring tools
SENTRY_DSN=your-sentry-dsn
POSTHOG_API_KEY=your-key
```

**For detailed configuration guide, see [CONFIGURATION.md](docs/CONFIGURATION.md)**

**In the nano editor:**
1. Use arrow keys to navigate
2. Replace `your-*` placeholders with actual values
3. Leave optional fields blank if not using
4. Press `Ctrl+X`, then `Y`, then `Enter` to save

**The script will validate your configuration and warn you of any issues before starting the application.**

### Step 5: Verify Installation

After the script completes, the application should be running automatically.

**Verify everything is working:**

```bash
# Check if all services are running
cd /opt/apps/esc
./status.sh

# Check security status (NEW)
/opt/bin/f2b-dashboard.sh

# View logs
./logs.sh
```

## Security Hardening

### 🛡️ Overview

This deployment includes **enterprise-grade security hardening** that protects against:

| Threat | Detection | Response | Duration |
|--------|-----------|----------|----------|
| Direct IP Access | Immediate | 403 Forbidden | 30 days (permanent) |
| SQL Injection | Pattern Match | Ban + Log | 30 days (permanent) |
| XSS Attacks | 3 occurrences | Ban + Log | 14 days |
| Vulnerability Scanners | User-Agent Match | Ban + Log | 14-30 days |
| Brute Force Login | 5 attempts/min | Rate Limit 429 | Until ban |
| DDoS Patterns | 100 req/min | Ban + Log | 1 hour |
| Directory Scanning | 3 attempts | Ban + Log | 30 days |
| File Inclusion (RFI/LFI) | 1 attempt | Ban + Log | 30 days (permanent) |
| Bad Bots (Nikto, Nmap) | User-Agent Match | Ban + Log | 14 days |

### Automatic Security Features

**Enabled automatically during deployment:**

✅ **Cloudflare-only IP Enforcement**
- Only Cloudflare IPs can access your application
- Non-Cloudflare IPs get 403 Forbidden
- Prevents direct IP bypassing of Cloudflare protection

✅ **Multi-layer Rate Limiting**
- General endpoints: 10 requests/second
- API endpoints: 30 requests/minute
- Login endpoints: 5 requests/minute
- Violators get 429 Too Many Requests + ban

✅ **Fail2Ban Threat Detection** (10 Jails)
- SSH brute force protection
- Vulnerability scanner detection
- SQL injection blocking
- XSS attack detection
- DDoS pattern recognition
- Bad bot/crawler blocking
- Directory enumeration protection
- File inclusion attack blocking

✅ **Automatic IP Banning**
- Offending IPs automatically blocked
- Ban times: 1 hour to 30 days depending on threat
- Permanent bans for critical threats (SQL injection, RFI/LFI)
- All bans logged in `/var/log/fail2ban-custom.log`

✅ **Real-time Security Monitoring**
- Dashboard showing active threats
- Recently banned IPs list
- Top offending IPs
- Ban activity timeline

### Managing Security

**See [SECURITY.md](docs/SECURITY.md) for comprehensive security guide**

#### View Security Status

```bash
# Real-time security dashboard
/opt/bin/f2b-dashboard.sh

# Output shows:
# - Per-jail statistics (banned IPs count)
# - Recently banned IPs with reasons
# - Top 10 offending IPs
# - Quick management commands
```

#### Monitor Security Events

```bash
# View all security events (real-time)
tail -f /var/log/fail2ban-custom.log

# View Fail2Ban decisions
tail -f /var/log/fail2ban.log

# View Nginx errors (400/403/429 responses)
tail -f /var/log/nginx/esc_error.log
```

#### Emergency: Unban an IP

If a legitimate IP was incorrectly banned:

```bash
# Unban specific IP from all jails
/opt/bin/f2b-unban.sh 192.168.1.100

# Manual unban from specific jail
sudo fail2ban-client set nginx-cloudflare-only unbanip 192.168.1.100
```

#### View Currently Banned IPs

```bash
# List all banned IPs via iptables
iptables -L -n | grep DROP

# Count total banned IPs
iptables -L -n | grep DROP | wc -l

# Get detailed stats
iptables -L -n -v | grep DROP
```

#### Disable Security (Not Recommended)

If you need to disable security for testing:

```bash
# Stop Fail2Ban
sudo systemctl stop fail2ban

# Disable on boot
sudo systemctl disable fail2ban

# Later, re-enable
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

### Security Features Not Enabled by Default

You can optionally add during re-deployment:

```bash
# Run deployment script again
cd /opt/apps/esc
./deploy.sh

# When asked "Enable security features?", choose "Y"
# When asked "Admin email for security alerts?", enter your email
```

## Configuration

### Nginx Configuration

Nginx configuration is located at `/etc/nginx/sites-available/esc`

The configuration includes:
- Cloudflare IP geo-blocking
- Multi-zone rate limiting
- Security headers
- Catch-all server for non-Cloudflare traffic

**Edit if needed:**

```bash
sudo nano /etc/nginx/sites-available/esc
```

**After changes, test and reload:**

```bash
# Test configuration
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx
```

### Fail2Ban Configuration

Fail2Ban configuration is located at `/etc/fail2ban/jail.local`

The configuration includes 10 specialized jails with different ban durations and thresholds.

**Edit if needed:**

```bash
sudo nano /etc/fail2ban/jail.local
```

**After changes, reload Fail2Ban:**

```bash
sudo systemctl reload fail2ban
```

**Common adjustments:**

```bash
# Increase ban duration for SQL injection
# Find: [nginx-sqli]
# Change: bantime = 2592000  (to longer duration)

# Decrease login rate limit threshold
# Find: [nginx-login-limit]
# Change: maxretry = 3  (from 5)
```

See [SECURITY.md](docs/SECURITY.md) for detailed Fail2Ban configuration guide.

### Docker Compose Configuration

The main docker-compose file is `compose.prod.yaml` in the app directory.

Key services:

- **redis**: Cache and message broker
- **web**: Django application (Gunicorn)
- **celery_worker**: Background task processor
- **celery_beat**: Scheduled task scheduler

### Systemd Service

The application runs as a systemd service for auto-start on boot:

```bash
# Check service status
sudo systemctl status esc

# Start service
sudo systemctl start esc

# Stop service
sudo systemctl stop esc

# Restart service
sudo systemctl restart esc

# Disable auto-start
sudo systemctl disable esc

# Enable auto-start
sudo systemctl enable esc
```

## Cloudflare Setup

Configure Cloudflare after installation is complete.

1. Sign up at [cloudflare.com](https://cloudflare.com) (free plan works)
2. Add your domain
3. Update your domain's nameservers to Cloudflare's nameservers
4. Wait for activation (usually 5-30 minutes)

### Step 1: Add Your Domain to Cloudflare

In Cloudflare DNS settings:

1. Add an **A record**:
   - Name: `@` (or your subdomain)
   - IPv4 address: Your VPS IP
   - Proxy status: **Proxied** (orange cloud) ← **IMPORTANT**

2. Optional: Add `www` subdomain:
   - Name: `www`
   - IPv4 address: Your VPS IP
   - Proxy status: **Proxied** (orange cloud)

**⚠️ CRITICAL**: The proxy status must be **Proxied** (orange cloud), not DNS only (gray cloud).

### Step 2: Configure SSL/TLS

1. Go to **SSL/TLS** → **Overview**
2. Set encryption mode to **Flexible** (if no SSL on VPS) or **Full** (if using Let's Encrypt)

3. Enable **Always Use HTTPS**:
   - Go to **SSL/TLS** → **Edge Certificates**
   - Toggle **Always Use HTTPS** to ON

### Step 3: Configure Static/Media Files (Optional)

If you're serving static/media files through Cloudflare:

1. Go to **Rules** → **Page Rules**
2. Create rules for caching static assets:
   - URL: `*your-domain.com/static/*`
   - Cache Level: Cache Everything
   - Edge Cache TTL: 1 month

### Step 4: Security Settings (Recommended)

1. **Firewall Rules**: Set to Medium or High
2. **Bot Fight Mode**: Enable
3. **Challenge Passage**: 30 minutes
4. **Browser Integrity Check**: Enable

### Step 5: Test Cloudflare Integration

```bash
# Check if traffic is going through Cloudflare
curl -I https://your-domain.com | grep CF-

# Should show headers like:
# CF-Cache-Status: HIT
# CF-RAY: 7d7c8e9f0a1b2c3d
```

**For detailed Cloudflare setup, see [CLOUDFLARE_SETUP.md](docs/CLOUDFLARE_SETUP.md)**

## Management

The installation creates several management scripts in `/opt/apps/esc/`:

### Deploy/Update Application

Pulls the latest image and restarts all services:

```bash
cd /opt/apps/esc
./deploy.sh
```

Use this whenever you:
- Update your Docker image
- Need to restart the application
- Deploy a new version

### Reconfigure Environment

Edit configuration and optionally restart:

```bash
cd /opt/apps/esc
./reconfig.sh
```

Use this when you need to:
- Change environment variables
- Update API keys or credentials
- Modify service configurations

### View Logs

View logs for all services:

```bash
cd /opt/apps/esc
./logs.sh
```

View logs for specific service:

```bash
./logs.sh web           # Django application
./logs.sh celery_worker # Celery worker
./logs.sh celery_beat   # Celery beat scheduler
./logs.sh redis         # Redis
```

### View Security Status (NEW)

```bash
cd /opt/apps/esc
./security.sh

# Or directly:
/opt/bin/f2b-dashboard.sh
```

Shows:
- Per-jail banned IP counts
- Recently banned IPs
- Top offending IPs
- Management commands

### Check Status

Check the status of all services and resource usage:

```bash
cd /opt/apps/esc
./status.sh
```

### Stop Application

Stop all services:

```bash
cd /opt/apps/esc
./stop.sh
```

### Start Application

Start all services:

```bash
cd /opt/apps/esc
./start.sh
```

### Direct Docker Compose Commands

You can also use Docker Compose directly:

```bash
cd /opt/apps/esc

# View running containers
docker compose -f compose.prod.yaml ps

# Restart specific service
docker compose -f compose.prod.yaml restart web

# View logs with follow
docker compose -f compose.prod.yaml logs -f web

# Execute command in container
docker compose -f compose.prod.yaml exec web python manage.py shell

# Run Django management commands
docker compose -f compose.prod.yaml exec web python manage.py migrate
docker compose -f compose.prod.yaml exec web python manage.py createsuperuser
docker compose -f compose.prod.yaml exec web python manage.py collectstatic
```

## Troubleshooting

### Application Won't Start

1. **Check Docker service**:
   ```bash
   sudo systemctl status docker
   ```

2. **Check logs**:
   ```bash
   cd /opt/apps/esc
   ./logs.sh
   ```

3. **Check environment variables**:
   ```bash
   cat /opt/apps/esc/.env.docker
   ```

4. **Verify Docker Hub login**:
   ```bash
   docker login
   ```

### Nginx Returns 502 Bad Gateway

This usually means the Django app isn't running:

1. **Check if containers are running**:
   ```bash
   docker ps
   ```

2. **Check web service health**:
   ```bash
   docker compose -f compose.prod.yaml ps
   ```

3. **Check web logs**:
   ```bash
   ./logs.sh web
   ```

4. **Restart the application**:
   ```bash
   ./deploy.sh
   ```

### Can't Access Website

1. **Check DNS propagation**:
   ```bash
   nslookup your-domain.com
   ```

2. **Check firewall**:
   ```bash
   sudo ufw status
   ```

3. **Check Nginx status**:
   ```bash
   sudo systemctl status nginx
   ```

4. **Check Nginx logs**:
   ```bash
   sudo tail -f /var/log/nginx/esc_error.log
   ```

5. **Verify Cloudflare settings**:
   - Ensure proxy is enabled (orange cloud)
   - Check SSL/TLS settings

### Legitimate IPs Getting Banned

If legitimate users are getting banned:

1. **Check which jail banned them**:
   ```bash
   grep "BANNED.*<IP>" /var/log/fail2ban-custom.log
   ```

2. **Unban the IP**:
   ```bash
   /opt/bin/f2b-unban.sh <IP>
   ```

3. **Whitelist the IP (optional)**:
   ```bash
   sudo nano /etc/fail2ban/jail.local
   # Add to [DEFAULT] section:
   ignoreip = 127.0.0.1 <IP>
   
   sudo systemctl reload fail2ban
   ```

4. **Adjust thresholds** (if needed):
   - See [SECURITY.md](docs/SECURITY.md) for threshold adjustments

### Server Under Attack

If your server is experiencing an attack:

1. **Check security dashboard**:
   ```bash
   /opt/bin/f2b-dashboard.sh
   ```

2. **View real-time bans**:
   ```bash
   tail -f /var/log/fail2ban-custom.log
   ```

3. **Check Cloudflare firewall rules**:
   - Log in to Cloudflare dashboard
   - Go to Security → WAF Rules
   - Add rules to block attack patterns

4. **Increase ban times temporarily**:
   ```bash
   sudo nano /etc/fail2ban/jail.local
   # Change: bantime = 86400  (to 604800 for 7 days)
   sudo systemctl reload fail2ban
   ```

See [SECURITY.md](docs/SECURITY.md) for emergency procedures.

### Celery Workers Not Processing Tasks

1. **Check worker status**:
   ```bash
   ./logs.sh celery_worker
   ```

2. **Check Redis connection**:
   ```bash
   docker compose -f compose.prod.yaml exec redis redis-cli ping
   ```

3. **Restart workers**:
   ```bash
   docker compose -f compose.prod.yaml restart celery_worker celery_beat
   ```

### Out of Disk Space

1. **Check disk usage**:
   ```bash
   df -h
   ```

2. **Clean up Docker resources**:
   ```bash
   # Remove unused containers, networks, images
   docker system prune -a
   
   # Remove old logs
   sudo journalctl --vacuum-time=7d
   ```

3. **Check log sizes**:
   ```bash
   du -sh /var/log/nginx/
   du -sh /opt/apps/esc/logs/
   ```

### Permission Issues

If you get permission errors:

1. **Fix ownership**:
   ```bash
   sudo chown -R $USER:$USER /opt/apps/esc
   ```

2. **Add user to Docker group**:
   ```bash
   sudo usermod -aG docker $USER
   newgrp docker
   ```

## Security Best Practices

### Keep System Updated

```bash
sudo apt update && sudo apt upgrade -y
```

### Use Strong Passwords

- Generate strong SECRET_KEY (done automatically)
- Use strong database passwords
- Enable 2FA on Docker Hub

### Firewall Configuration

```bash
# Check firewall status
sudo ufw status verbose

# Only allow necessary ports
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 443/tcp  # HTTPS
```

### Limit SSH Access

```bash
# Edit SSH config
sudo nano /etc/ssh/sshd_config

# Disable root login
PermitRootLogin no

# Use SSH keys only
PasswordAuthentication no

# Restart SSH
sudo systemctl restart sshd
```

### Monitor Logs Regularly

```bash
# Check for suspicious activity
sudo tail -f /var/log/auth.log
sudo tail -f /var/log/nginx/esc_access.log

# Check security events
tail -f /var/log/fail2ban-custom.log
```

### Security Layers

**This deployment includes 5 layers of security:**

1. **Cloudflare** - DDoS protection, WAF, bot protection
2. **Nginx** - Cloudflare-only enforcement, rate limiting, headers
3. **Fail2Ban** - Threat detection and automatic IP banning
4. **Django** - CSRF protection, SQL escaping, secure defaults
5. **Application** - Business logic security

### Automatic Security Features

✅ Cloudflare-only IP enforcement  
✅ Multi-layer rate limiting  
✅ Vulnerability scanner blocking  
✅ SQL injection prevention  
✅ XSS attack detection  
✅ DDoS pattern recognition  
✅ Bad bot blocking  
✅ Automatic IP banning  
✅ Comprehensive logging  
✅ Real-time monitoring  

**See [SECURITY.md](docs/SECURITY.md) for comprehensive security guide.**

## Backup and Restore

### Backup

Create a backup script `/opt/apps/esc/backup.sh`:

```bash
#!/bin/bash
BACKUP_DIR="/opt/backups/esc"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup volumes
docker run --rm \
  -v esc_redis_data:/data \
  -v $BACKUP_DIR:/backup \
  alpine tar czf /backup/redis_${DATE}.tar.gz /data

docker run --rm \
  -v esc_logs_data:/data \
  -v $BACKUP_DIR:/backup \
  alpine tar czf /backup/logs_${DATE}.tar.gz /data

# Backup environment
cp /opt/apps/esc/.env.docker $BACKUP_DIR/env_${DATE}.docker

# Backup Nginx config
cp /etc/nginx/sites-available/esc $BACKUP_DIR/nginx_${DATE}.conf

# Backup Fail2Ban config (NEW)
sudo cp /etc/fail2ban/jail.local $BACKUP_DIR/fail2ban_${DATE}.local

echo "Backup completed: $BACKUP_DIR"
```

Run backup:

```bash
chmod +x /opt/apps/esc/backup.sh
./backup.sh
```

### Automated Backups

Set up daily backups with cron:

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * /opt/apps/esc/backup.sh
```

### Restore

To restore from backup:

```bash
# Stop services
cd /opt/apps/esc
./stop.sh

# Restore volumes
docker run --rm \
  -v esc_redis_data:/data \
  -v /opt/backups/esc:/backup \
  alpine tar xzf /backup/redis_YYYYMMDD_HHMMSS.tar.gz -C /

# Restore environment
cp /opt/backups/esc/env_YYYYMMDD_HHMMSS.docker /opt/apps/esc/.env.docker

# Restore Fail2Ban config (NEW)
sudo cp /opt/backups/esc/fail2ban_YYYYMMDD_HHMMSS.local /etc/fail2ban/jail.local
sudo systemctl reload fail2ban

# Start services
./start.sh
```

## Updates and Maintenance

### Update Application

When a new version is released:

```bash
cd /opt/apps/esc
./deploy.sh

# The script will detect your existing installation:
# ✓ Existing deployment detected!
# Use existing configuration? [Y/n]: Y
# 
# Only asks for Docker password, then:
# - Pulls latest code
# - Updates containers
# - Restarts services
# - Preserves all security configuration
```

**Smart Re-deployment**:
- Preserves your domain, SSL, and configuration
- Preserves all security settings (Fail2Ban, rate limiting)
- Skips already-configured components
- Only updates what's changed
- See [REDEPLOYMENT.md](docs/REDEPLOYMENT.md) for details

### Update System Packages

Monthly maintenance:

```bash
# Update packages
sudo apt update
sudo apt upgrade -y

# Clean up
sudo apt autoremove -y
sudo apt autoclean

# Restart if kernel updated
sudo reboot
```

### Update Docker

```bash
# Update Docker
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Restart Docker
sudo systemctl restart docker
```

### Monitor Resource Usage

Regular monitoring:

```bash
# Check disk space
df -h

# Check memory
free -h

# Check CPU and load
top

# Check Docker stats
docker stats

# Check service status
./status.sh

# Check security status (NEW)
/opt/bin/f2b-dashboard.sh
```

### Log Rotation

Logs are automatically rotated by Docker (configured in compose file) and logrotate (for Fail2Ban).

Check log sizes:

```bash
# Docker logs
docker inspect --format='{{.LogPath}}' $(docker ps -q) | xargs du -h

# Nginx logs
du -h /var/log/nginx/

# Fail2Ban logs (NEW)
du -h /var/log/fail2ban*
```

Manually clear old logs:

```bash
# Clear Docker logs
truncate -s 0 $(docker inspect --format='{{.LogPath}}' $(docker ps -q))

# Rotate Nginx logs
sudo logrotate -f /etc/logrotate.d/nginx
```

## Performance Tuning

### Optimize Celery Workers

Edit `compose.prod.yaml` to adjust worker concurrency:

```yaml
celery_worker:
  command: >
    celery -A esc worker
    --loglevel=info
    --concurrency=8  # Increase for more concurrent tasks
    --prefetch-multiplier=1
```

### Optimize Redis

For high-traffic applications, consider:

```yaml
redis:
  command: ["redis-server", "--appendonly", "yes", "--maxmemory", "256mb", "--maxmemory-policy", "allkeys-lru"]
```

### Nginx Caching

Add caching to Nginx configuration for better performance.

## Support

### Getting Help

1. **Check logs first**: Most issues can be diagnosed from logs
2. **GitHub Issues**: Report bugs or request features
3. **Documentation**: Re-read relevant sections
4. **Community**: Django and Docker communities

### Useful Resources

- [Django Documentation](https://docs.djangoproject.com/)
- [Docker Documentation](https://docs.docker.com/)
- [Nginx Documentation](https://nginx.org/en/docs/)
- [Celery Documentation](https://docs.celeryproject.org/)
- [Cloudflare Documentation](https://developers.cloudflare.com/)

## License

This deployment configuration is provided as-is for the ESC Django application.

---

**Last Updated**: December 2025

**Maintainer**: Andreas Tuko

**Repository**: https://github.com/andreas-tuko/esc-compose-prod
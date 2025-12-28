# ESC Django Application - Production Deployment Guide

Complete guide for deploying the ESC Django application on a VPS with Docker, Nginx, and Cloudflare.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Installation](#detailed-installation)
- [Configuration](#configuration)
- [Cloudflare Setup](#cloudflare-setup)
- [Management](#management)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Backup and Restore](#backup-and-restore)
- [Updates and Maintenance](#updates-and-maintenance)

## Overview

This deployment setup provides a production-ready environment for the ESC Django application with:

- **Docker Compose** for container orchestration
- **Nginx** as reverse proxy
- **Redis** for caching and message broker
- **Celery** for async task processing
- **Celery Beat** for scheduled tasks
- **Cloudflare** for SSL, CDN, and DDoS protection

## Architecture

```
Internet → Cloudflare → VPS (Your Server)
                          ↓
                        Nginx (Port 80/443)
                          ↓
                     Django App (Port 8000)
                          ↓
                  ┌───────┴────────┐
                  ↓                ↓
            Celery Worker    Celery Beat
                  ↓                ↓
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
# - Installation preferences

# 4. Configure your environment
nano /opt/apps/esc/.env.docker

# 5. Restart the application
cd /opt/apps/esc
./deploy.sh
```

That's it! Your application should now be running.

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

6. **Environment Configuration**: **Interactive editor opens automatically**
   - SECRET_KEY is auto-generated ✓
   - Domain is pre-configured ✓
   - You configure: Email, Database, and optional services
   - Built-in validation ensures correct configuration
   - See [CONFIGURATION.md](CONFIGURATION.md) for detailed guide

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
9. ✅ Installs and configures Nginx
10. ✅ Sets up systemd service for auto-start
11. ✅ Configures firewall (if selected)
12. ✅ Creates management scripts
13. ✅ Pulls Docker images and starts services

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

**For detailed configuration guide, see [CONFIGURATION.md](CONFIGURATION.md)**

**In the nano editor:**
1. Use arrow keys to navigate
2. Replace `your-*` placeholders with actual values
3. Leave optional fields blank if not using
4. Press `Ctrl+X`, then `Y`, then `Enter` to save

**The script will validate your configuration and warn you of any issues before starting the application.**

### Step 5: Verify Installation

After the script completes, the application should be running automatically.

Cloudflare provides SSL, CDN, and DDoS protection for your application.

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
   - Proxy status: **Proxied** (orange cloud)

2. Optional: Add `www` subdomain:
   - Name: `www`
   - IPv4 address: Your VPS IP
   - Proxy status: **Proxied**

### Step 3: Configure SSL/TLS

1. Go to **SSL/TLS** → **Overview**
2. Set encryption mode to **Flexible** or **Full**
   - Use **Flexible** if you don't have SSL on your VPS (our setup)
   - Use **Full** if you add SSL certificates to Nginx later

3. Enable **Always Use HTTPS**:
   - Go to **SSL/TLS** → **Edge Certificates**
   - Toggle **Always Use HTTPS** to ON

### Step 4: Configure Static/Media Files (Optional)

If you're serving static/media files through Cloudflare:

1. Go to **Rules** → **Page Rules**
2. Create rules for caching static assets:
   - URL: `*your-domain.com/static/*`
   - Cache Level: Cache Everything
   - Edge Cache TTL: 1 month

### Step 5: Security Settings (Recommended)

1. **Firewall Rules**: Set to Medium or High
2. **Bot Fight Mode**: Enable
3. **Challenge Passage**: 30 minutes
4. **Browser Integrity Check**: Enable

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

## Configuration

### Nginx Configuration

Nginx configuration is located at `/etc/nginx/sites-available/esc`

Edit if needed:

```bash
sudo nano /etc/nginx/sites-available/esc
```

After changes, test and reload:

```bash
# Test configuration
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx
```

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

## Security

### Best Practices

1. **Keep system updated**:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

2. **Use strong passwords**:
   - Generate strong SECRET_KEY
   - Use strong database passwords
   - Enable 2FA on Docker Hub

3. **Firewall configuration**:
   ```bash
   # Check firewall status
   sudo ufw status verbose
   
   # Only allow necessary ports
   sudo ufw allow 22/tcp   # SSH
   sudo ufw allow 80/tcp   # HTTP
   sudo ufw allow 443/tcp  # HTTPS
   ```

4. **Limit SSH access**:
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

5. **Monitor logs regularly**:
   ```bash
   # Check for suspicious activity
   sudo tail -f /var/log/auth.log
   sudo tail -f /var/log/nginx/esc_access.log
   ```

### Security Headers

Nginx is configured with security headers:
- X-Frame-Options
- X-Content-Type-Options
- X-XSS-Protection

### Cloudflare Protection

Cloudflare provides:
- DDoS protection
- Rate limiting
- Bot protection
- Web Application Firewall (WAF)

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

# Start services
./start.sh
```

## Updates and Maintenance

### Update Application

When a new version is released:

```bash
cd /opt/apps/esc
./deploy.sh
```

This will:
1. Pull the latest Docker image
2. Stop old containers
3. Start new containers
4. Verify health checks

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
```

### Log Rotation

Logs are automatically rotated by Docker (configured in compose file).

Check log sizes:

```bash
# Docker logs
docker inspect --format='{{.LogPath}}' $(docker ps -q) | xargs du -h

# Nginx logs
du -h /var/log/nginx/
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
# Quick Start Guide - ESC Django Deployment

Get your ESC Django application running in 5 minutes.

## Prerequisites Checklist

Before you start, ensure you have:

- [ ] A VPS with Ubuntu 20.04+ or Debian 11+ (minimum 2GB RAM)
- [ ] SSH access to the VPS
- [ ] A domain name (e.g., `example.com`)
- [ ] Domain DNS pointed to your VPS IP address
- [ ] Cloudflare account (free tier)
- [ ] Docker Hub credentials (username and password)

## Step 1: Connect to Your VPS

```bash
ssh your-username@your-server-ip
```

## Step 2: Run the Deployment Script

Copy and paste this entire command:

```bash
curl -fsSL https://raw.githubusercontent.com/andreas-tuko/esc-compose-prod/main/deploy.sh -o deploy.sh && chmod +x deploy.sh && ./deploy.sh
```

## Step 3: Answer the Prompts

The script will ask you for:

1. **Domain name**: Enter your domain (e.g., `example.com`)
2. **Docker Hub username**: Your Docker Hub username
3. **Docker Hub password**: Your Docker Hub password or token
4. **Application directory**: Press Enter for default (`/opt/apps/esc`)
5. **Create deployer user**: Press Enter for Yes (recommended)
6. **Configure firewall**: Press Enter for Yes (recommended)
7. **Confirmation**: Press Enter to proceed

## Step 4: Configure Environment Variables

**The script will automatically open a nano editor** with your environment file pre-configured with:
- Auto-generated SECRET_KEY ✓
- Your domain in ALLOWED_HOSTS ✓
- Sensible defaults ✓

**You need to configure:**

### Required (Must configure):
- `EMAIL_HOST_USER` - Your email address
- `EMAIL_HOST_PASSWORD` - Your email password/app password
- `DATABASE_URL` - If using PostgreSQL (optional if using SQLite)

### Optional (Configure if using these features):
- Cloudflare R2 credentials (for file storage)
- M-Pesa credentials (for payments)
- Google OAuth (for social login)
- Sentry & PostHog (for monitoring)

**Tips for editing:**
- Use arrow keys to navigate
- Replace `your-*` placeholders with actual values
- Leave optional fields if not using those features
- Press `Ctrl+X`, then `Y`, then `Enter` to save

The script will validate your configuration before proceeding!

## Step 5: Finish Installation

After configuring the environment:
- The script validates your configuration
- If everything is correct, it starts the application automatically
- If there are issues, you'll be prompted to fix them

### DNS Settings

1. Log in to [Cloudflare](https://dash.cloudflare.com)
2. Select your domain
3. Go to **DNS** → **Records**
4. Add an A record:
   - **Type**: A
   - **Name**: @ (for root domain) or your subdomain
   - **IPv4 address**: Your VPS IP address
   - **Proxy status**: Proxied (orange cloud icon)
   - Click **Save**

### SSL/TLS Settings

1. Go to **SSL/TLS** → **Overview**
2. Set encryption mode to **Flexible**
3. Go to **SSL/TLS** → **Edge Certificates**
4. Enable **Always Use HTTPS**

## Step 6: Configure Cloudflare

Wait 2-3 minutes for services to fully start, then visit:

```
http://your-domain.com
```

You should see your application running!

## Step 7: Verify Installation

```bash
# View logs
cd /opt/apps/esc && ./logs.sh

# Check status
cd /opt/apps/esc && ./status.sh

# Restart application
cd /opt/apps/esc && ./deploy.sh

# Stop application
cd /opt/apps/esc && ./stop.sh

# Start application
cd /opt/apps/esc && ./start.sh
```

## Troubleshooting

### Can't access the website?

1. **Check DNS propagation**: Use [DNS Checker](https://dnschecker.org)
2. **Wait a few minutes**: Services need time to start
3. **Check logs**: `cd /opt/apps/esc && ./logs.sh`
4. **Verify Cloudflare**: Ensure proxy is enabled (orange cloud)

### Getting 502 Bad Gateway?

```bash
# Check if containers are running
cd /opt/apps/esc
docker compose -f compose.prod.yaml ps

# Check web service logs
./logs.sh web

# Restart services
./deploy.sh
```

### Docker permission errors?

```bash
# Log out and log back in, or run:
newgrp docker
```

## Next Steps

Now that your application is running:

1. **Configure email** (optional): Edit `.env.docker` and add email settings
2. **Create superuser**: 
   ```bash
   cd /opt/apps/esc
   docker compose -f compose.prod.yaml exec web python manage.py createsuperuser
   ```
3. **Set up backups**: See [README.md](README.md#backup-and-restore)
4. **Monitor logs regularly**: `./logs.sh`
5. **Keep system updated**: `sudo apt update && sudo apt upgrade -y`

## Getting Help

- **Full documentation**: See [README.md](README.md)
- **Check logs first**: Most issues are visible in logs
- **GitHub Issues**: Report bugs at the repository

## Security Reminders

- [ ] Change the SECRET_KEY in `.env.docker`
- [ ] Use strong passwords everywhere
- [ ] Enable UFW firewall
- [ ] Keep your system updated
- [ ] Monitor logs for suspicious activity
- [ ] Set up automated backups

---

**Congratulations!** 🎉 Your ESC Django application is now live!

For detailed documentation, see [README.md](README.md)
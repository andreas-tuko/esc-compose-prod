# ESC Operations Guide - Day-to-Day Management & Monitoring

Guide for running and maintaining your ESC deployment on a daily basis.

## Quick Reference

### Common Commands Cheat Sheet

```bash
# Navigation
cd /opt/apps/esc

# View status
./status.sh              # Service & resource status
./security.sh            # Security dashboard (Fail2Ban)

# View logs
./logs.sh                # All services
./logs.sh web            # Just Django app
./logs.sh celery_worker  # Just Celery

# Manage services
./start.sh               # Start all services
./stop.sh                # Stop all services
./deploy.sh              # Update and restart

# Configure
./reconfig.sh            # Edit environment variables

# Security
/opt/bin/f2b-dashboard.sh    # Security dashboard
/opt/bin/f2b-unban.sh <IP>   # Unban IP
```

## Daily Operations

### Morning Check (2 minutes)

Start each day with this routine:

```bash
# 1. Check if application is running
cd /opt/apps/esc
./status.sh

# 2. Look for any errors in logs
./logs.sh web | tail -20

# 3. Check security status
/opt/bin/f2b-dashboard.sh

# 4. Note any concerning patterns in security dashboard
```

**Expected output:**
- ✅ All containers show "running"
- ✅ No ERROR logs in past 12 hours
- ✅ Fail2Ban shows 0-50 bans depending on traffic

### Weekly Maintenance (30 minutes)

Run these tasks once per week:

```bash
# 1. Update system packages
sudo apt update
sudo apt upgrade -y

# 2. Clean Docker resources
docker system prune -a

# 3. Check disk space
df -h /

# 4. Review security logs (past 7 days)
grep "$(date -d '7 days ago' '+%Y-%m-%d')" /var/log/fail2ban-custom.log | head -20

# 5. Check for certificate renewal (if using Let's Encrypt)
sudo certbot renew --dry-run

# 6. Backup configuration
./backup.sh

# 7. Review resource usage trends
free -h
docker stats --no-stream
```

### Monthly Maintenance (1-2 hours)

Run these tasks once per month:

```bash
# 1. Full system update
sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y

# 2. Review and rotate logs
du -sh /var/log/
sudo logrotate -f /etc/logrotate.d/nginx
sudo logrotate -f /etc/logrotate.d/fail2ban

# 3. Database optimization (if applicable)
docker compose -f compose.prod.yaml exec web python manage.py migrate --noinput

# 4. Clear old caches
docker compose -f compose.prod.yaml exec redis redis-cli FLUSHDB

# 5. Security audit
/opt/bin/f2b-dashboard.sh
grep "BANNED" /var/log/fail2ban-custom.log | tail -100 | head -50

# 6. Full backup
./backup.sh
ls -lh /opt/backups/esc/ | tail -10

# 7. Performance review
docker stats --no-stream
docker compose -f compose.prod.yaml logs web | grep -i "error\|warning" | wc -l
```

## Monitoring

### Real-Time Monitoring

#### Monitor Application Logs

```bash
cd /opt/apps/esc

# Follow all services
./logs.sh

# Follow specific service
./logs.sh web
./logs.sh celery_worker
./logs.sh celery_beat
./logs.sh redis

# Follow with grep filter
./logs.sh web | grep ERROR
```

#### Monitor Security Events

```bash
# Real-time security dashboard
watch -n 5 /opt/bin/f2b-dashboard.sh

# Or follow custom ban log
tail -f /var/log/fail2ban-custom.log

# Or watch Nginx errors
tail -f /var/log/nginx/esc_error.log
```

#### Monitor Resource Usage

```bash
# Docker container resource usage
docker stats

# System-wide resource usage
top
free -h
df -h

# Network connections
netstat -an | grep ESTABLISHED | wc -l

# Nginx connections
sudo ss -an | grep :80 | wc -l
sudo ss -an | grep :443 | wc -l
```

### Scheduled Monitoring

Set up automated monitoring with cron jobs:

```bash
# Edit crontab
crontab -e

# Add these lines:

# Daily security check at 8 AM
0 8 * * * /opt/bin/f2b-dashboard.sh > /tmp/daily-security-report.txt 2>&1

# Weekly log rotation at Sunday 3 AM
0 3 * * 0 sudo logrotate -f /etc/logrotate.d/nginx /etc/logrotate.d/fail2ban

# Daily backup at 2 AM
0 2 * * * /opt/apps/esc/backup.sh >> /var/log/backup.log 2>&1

# Hourly disk space check
0 * * * * df -h / | tail -1 >> /var/log/disk-usage.log

# System health check every 6 hours
0 */6 * * * docker compose -f /opt/apps/esc/compose.prod.yaml ps >> /var/log/docker-health.log 2>&1
```

## Scaling & Performance

### Monitor Performance Metrics

Track these metrics weekly:

```bash
# CPU Usage
top -b -n 1 | grep "Cpu(s)"

# Memory Usage
free -h

# Disk I/O
iostat -x 1 5

# Network I/O
iftop -n

# Docker memory per container
docker stats --no-stream

# Nginx active connections
sudo ss -an | grep :80 | grep ESTABLISHED | wc -l
sudo ss -an | grep :443 | grep ESTABLISHED | wc -l
```

### Scale Celery Workers

If background tasks are slow:

```bash
# Edit compose.prod.yaml
sudo nano /etc/docker/compose.prod.yaml

# Find celery_worker section and increase concurrency:
celery_worker:
  command: >
    celery -A esc worker
    --loglevel=info
    --concurrency=8      # Increase from default
    --prefetch-multiplier=1

# Restart
./deploy.sh
```

### Optimize Redis

If Redis memory usage is high:

```bash
# Check Redis memory
docker compose -f compose.prod.yaml exec redis redis-cli INFO memory

# Configure memory limit in docker-compose.yaml
redis:
  command: ["redis-server", "--maxmemory", "256mb", "--maxmemory-policy", "allkeys-lru"]

# Restart
./deploy.sh
```

## Troubleshooting & Recovery

### Application Not Responding

```bash
# 1. Check if running
docker compose -f compose.prod.yaml ps

# 2. Check logs
./logs.sh web

# 3. Check container health
docker compose -f compose.prod.yaml ps | grep web

# 4. Restart application
./deploy.sh

# 5. Check system resources
free -h
df -h
```

### High Memory Usage

```bash
# 1. Identify memory hog
docker stats

# 2. Check what containers are using memory
docker compose -f compose.prod.yaml top web
docker compose -f compose.prod.yaml top celery_worker

# 3. Check Redis memory
docker compose -f compose.prod.yaml exec redis redis-cli INFO memory

# 4. Clear Redis cache
docker compose -f compose.prod.yaml exec redis redis-cli FLUSHDB

# 5. If persistent, restart services
./stop.sh
sleep 10
./start.sh
```

### High CPU Usage

```bash
# 1. Check which processes are consuming CPU
top

# 2. Check if Celery workers are stuck
./logs.sh celery_worker | tail -20

# 3. Check for Django errors
./logs.sh web | grep ERROR | tail -20

# 4. Check system processes
ps aux | grep -E "python|celery|nginx" | head -10

# 5. Restart Celery workers
docker compose -f compose.prod.yaml restart celery_worker
```

### Disk Space Running Low

```bash
# 1. Check disk usage
df -h

# 2. Find large files
du -sh /var/log/*
du -sh /opt/apps/esc/*

# 3. Clean Docker logs
docker exec CONTAINER_ID truncate -s 0 /var/log/app.log

# 4. Compress old logs
gzip /var/log/nginx/*.log.*
gzip /var/log/fail2ban*.log.*

# 5. Clean Docker system
docker system prune -a

# 6. Emergency: backup and delete old backups
ls -la /opt/backups/esc/ | head -20
rm /opt/backups/esc/older_backups_*.tar.gz
```

### Connection Timeouts

```bash
# 1. Check network connectivity
ping 8.8.8.8

# 2. Check DNS resolution
nslookup your-domain.com

# 3. Check Nginx upstream
curl -v http://127.0.0.1:8000/health

# 4. Check firewall rules
sudo ufw status

# 5. Check port listening
sudo ss -tlnp | grep -E ":80|:443|:8000"

# 6. Check Cloudflare connectivity
curl -I https://your-domain.com
```

## Security Monitoring

### Daily Security Checklist

```bash
# 1. View security dashboard
/opt/bin/f2b-dashboard.sh

# 2. Check for suspicious activity
tail -n 50 /var/log/fail2ban-custom.log

# 3. Monitor failed logins
grep "Failed password" /var/log/auth.log | tail -20

# 4. Check for port scanning attempts
tail -n 20 /var/log/ufw.log

# 5. Monitor firewall blocks
sudo ufw status verbose
```

### Security Incident Response

**If you notice unusual activity:**

```bash
# 1. Gather information
/opt/bin/f2b-dashboard.sh
tail -n 100 /var/log/fail2ban-custom.log > /tmp/incident-report.txt

# 2. Identify attack pattern
grep "BANNED" /var/log/fail2ban-custom.log | awk '{print $7}' | sort | uniq -c | sort -rn | head -10

# 3. Get attacker IP details
geoiplookup <IP>

# 4. Check Cloudflare logs
# Log into Cloudflare dashboard → Analytics & Logs

# 5. If under attack, increase ban times temporarily
sudo nano /etc/fail2ban/jail.local
# Change: bantime = 86400 to bantime = 604800 (7 days)
sudo systemctl reload fail2ban

# 6. Consider adding Cloudflare WAF rule
# Cloudflare dashboard → Security → WAF Rules → Create Rule
```

## Database Operations

### Create Backups

```bash
# Manual backup
cd /opt/apps/esc
./backup.sh

# Or manually
docker run --rm \
  -v esc_redis_data:/data \
  -v /opt/backups/esc:/backup \
  alpine tar czf /backup/redis_$(date +%Y%m%d_%H%M%S).tar.gz /data
```

### Restore from Backup

```bash
# 1. Stop services
./stop.sh

# 2. Restore Redis
docker run --rm \
  -v esc_redis_data:/data \
  -v /opt/backups/esc:/backup \
  alpine tar xzf /backup/redis_YYYYMMDD_HHMMSS.tar.gz -C /

# 3. Restore environment (if changed)
cp /opt/backups/esc/env_YYYYMMDD_HHMMSS.docker .env.docker

# 4. Start services
./start.sh

# 5. Verify
./status.sh
```

### Database Cleanup

```bash
# Redis memory usage
docker compose -f compose.prod.yaml exec redis redis-cli INFO memory

# Clear expired cache
docker compose -f compose.prod.yaml exec redis redis-cli FLUSHDB

# Optimize Redis database
docker compose -f compose.prod.yaml exec redis redis-cli BGSAVE
```

## Common Issues & Solutions

### 502 Bad Gateway

**Cause**: Django app not responding

**Solution**:
```bash
./logs.sh web          # Check for errors
./deploy.sh            # Restart
```

### 429 Too Many Requests

**Cause**: Rate limit exceeded (intentional)

**Check if legitimate**:
```bash
tail -n 50 /var/log/nginx/esc_access.log | grep 429
```

**If legitimate user**: 
```bash
/opt/bin/f2b-unban.sh <IP>
```

### Celery Tasks Not Running

**Solution**:
```bash
./logs.sh celery_worker     # Check for errors
docker compose -f compose.prod.yaml restart celery_worker celery_beat
redis-cli ping              # Verify Redis
```

### SSL Certificate Expired

**For Let's Encrypt**:
```bash
sudo certbot renew --force-renewal
sudo systemctl reload nginx
```

**For Self-signed**:
```bash
sudo ./scripts/renew-selfsigned.sh  # Or create new
sudo systemctl reload nginx
```

## Documentation

### Key Files to Know

| File | Purpose | Edit? |
|------|---------|-------|
| `/opt/apps/esc/.env.docker` | Environment config | ✅ Frequently |
| `/opt/apps/esc/compose.prod.yaml` | Docker Compose | ✅ For scaling |
| `/etc/nginx/sites-available/esc` | Nginx config | ⚠️ With care |
| `/etc/fail2ban/jail.local` | Security config | ⚠️ With care |
| `/var/log/fail2ban-custom.log` | Security log | ❌ Read-only |
| `/var/log/nginx/esc_access.log` | Request log | ❌ Read-only |

### Getting Help

```bash
# Check Nginx syntax
sudo nginx -t

# Test Fail2Ban config
sudo fail2ban-client start

# View Docker Compose documentation
docker compose --help

# Check Django logs
./logs.sh web | head -100
```

## Contact & Escalation

For issues you can't resolve:

1. Check `/opt/apps/esc/docs/TROUBLESHOOTING.md`
2. Review `/opt/apps/esc/docs/SECURITY.md` for security issues
3. Check GitHub issues: https://github.com/andreas-tuko/esc-compose-prod
4. Reach out to the development team

---

**Last Updated**: January 2026  
**Version**: 1.0
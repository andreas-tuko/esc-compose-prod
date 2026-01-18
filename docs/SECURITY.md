# ESC Security Guide - Fail2Ban, Rate Limiting & Threat Detection

Complete guide to security hardening features, management, and emergency procedures.

## Table of Contents

- [Overview](#overview)
- [Security Architecture](#security-architecture)
- [Threat Protection](#threat-protection)
- [Fail2Ban Configuration](#fail2ban-configuration)
- [Rate Limiting](#rate-limiting)
- [Monitoring & Logging](#monitoring--logging)
- [Management Commands](#management-commands)
- [Emergency Procedures](#emergency-procedures)
- [Troubleshooting](#troubleshooting)
- [Advanced Configuration](#advanced-configuration)

## Overview

This deployment includes **5 layers of security**:

1. **Cloudflare** - Edge protection, DDoS, WAF
2. **Nginx** - Cloudflare-only enforcement, rate limiting
3. **Fail2Ban** - Threat detection, automatic banning
4. **Django** - Application-level security
5. **Firewall** - Network-level protection (UFW)

## Security Architecture

```
┌─────────────────────────────────────────────┐
│          Internet Attacker                   │
└────────────────────┬────────────────────────┘
                     │
           ┌─────────▼─────────┐
           │   Cloudflare DDoS │
           │   Bot Protection  │
           │   WAF Rules       │
           └─────────┬─────────┘
                     │
           ┌─────────▼──────────────────┐
           │ Fail2Ban Threat Detection  │
           │ - 10 Specialized Jails    │
           │ - Pattern Matching        │
           │ - Automatic IP Banning    │
           └─────────┬──────────────────┘
                     │
           ┌─────────▼──────────────────┐
           │    Nginx (Port 80/443)     │
           │ - Cloudflare-only enforce  │
           │ - Rate limiting            │
           │ - Security headers         │
           │ - Reverse proxy            │
           └─────────┬──────────────────┘
                     │
           ┌─────────▼──────────────────┐
           │ Django Application         │
           │ - CSRF protection          │
           │ - SQL escaping             │
           │ - Authentication           │
           │ - Business logic           │
           └─────────┬──────────────────┘
                     │
           ┌─────────▼──────────────────┐
           │  Redis + Database          │
           │ - Connection security      │
           │ - Data encryption          │
           └────────────────────────────┘
```

## Threat Protection

### Threat Matrix

| Threat | Detection | Trigger | Response | Duration |
|--------|-----------|---------|----------|----------|
| **Direct IP Access** | Nginx geo-block | First request | 403 Forbidden | 30 days |
| **SQL Injection** | Pattern in URL/params | 1 attempt | Ban + Log | 30 days ⚠️ |
| **XSS Attack** | `<script>` or JS patterns | 3 occurrences | Ban + Log | 14 days |
| **Vulnerability Scanner** | Known User-Agent | 2 attempts | Ban + Log | 14-30 days |
| **Directory Enumeration** | Scanning patterns | 3 attempts | Ban + Log | 30 days |
| **File Inclusion (RFI/LFI)** | Path traversal patterns | 1 attempt | Ban + Log | 30 days ⚠️ |
| **Brute Force Login** | 429 responses | 3 violations | Rate limit | 24 hours |
| **SSH Brute Force** | Auth failures | 3 failures | Ban | 7 days |
| **DDoS Pattern** | Request volume | 100 req/min | Ban | 1 hour |
| **Bad Bot** | User-Agent match | 1 request | Ban + Log | 14 days |

⚠️ = Permanent bans for critical threats

### Banned User-Agents (Automatic Detection)

Automatically detected and banned for 14 days:

- `nikto` - Vulnerability scanner
- `nmap` - Network mapper
- `masscan` - Port scanner
- `zap` - OWASP ZAP
- `burp` - Burp Suite
- `sqlmap` - SQL injection tool
- `metasploit` - Exploitation framework
- `havij` - SQL injection tool
- `acunetix` - Web scanner
- `curl` (without proper headers)
- `wget` - Web crawler

## Fail2Ban Configuration

### Installed Jails

All jails are installed and enabled by default:

#### 1. **sshd** - SSH Brute Force Protection
```ini
[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3        # Ban after 3 failed attempts
bantime = 604800    # 7 days
findtime = 600      # Within 10 minutes
```

**Use case**: Prevents SSH login brute force attacks

---

#### 2. **nginx-cloudflare-only** - Non-Cloudflare Access Blocking
```ini
[nginx-cloudflare-only]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_error.log
maxretry = 1        # Ban immediately on first non-CF request
bantime = 2592000   # 30 days (PERMANENT)
findtime = 300      # Within 5 minutes
```

**Use case**: Blocks direct IP access, forces Cloudflare usage

---

#### 3. **nginx-bad-requests** - HTTP Error Response Detection
```ini
[nginx-bad-requests]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 5        # Ban after 5 bad requests
bantime = 86400     # 24 hours
findtime = 600      # Within 10 minutes
```

**Detects**: 400, 403, 429, 444 responses

---

#### 4. **nginx-rate-limit** - 429 Too Many Requests
```ini
[nginx-rate-limit]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 3        # Ban after 3 rate limit violations
bantime = 86400     # 24 hours
findtime = 300      # Within 5 minutes
```

**Use case**: Prevents automated attacks that trigger rate limits

---

#### 5. **nginx-noscript** - Vulnerability Scanner Detection
```ini
[nginx-noscript]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 2        # Ban after 2 scanner requests
bantime = 1209600   # 14 days
findtime = 600      # Within 10 minutes
```

**Detects**:
- `.php` file requests
- `.asp` file requests
- `.cgi` file requests
- `wp-admin/` (WordPress)
- `wp-login` (WordPress)
- `xmlrpc.php` (WordPress)
- `shell.php`, `backdoor`, `admin.php`

---

#### 6. **nginx-scan** - Directory & File Enumeration
```ini
[nginx-scan]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 3        # Ban after 3 scan attempts
bantime = 604800    # 30 days
findtime = 600      # Within 10 minutes
```

**Detects**:
- `/admin`, `/api`, `/backup`, `/config`
- `/database`, `/wp-content`, `/uploads`
- `/files`, `/includes`, `/themes`, `/plugins`
- `/.env`, `/.git`, `/.aws`, `/.ssh`
- `/.htaccess`, `/web.config`

---

#### 7. **nginx-sqli** - SQL Injection Attempts
```ini
[nginx-sqli]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 1        # Ban immediately (ZERO TOLERANCE)
bantime = 2592000   # 30 days (PERMANENT)
findtime = 300      # Within 5 minutes
```

**Detects SQL keywords**:
- `union`, `select`, `insert`, `update`, `delete`
- `drop`, `create`, `alter`, `exec`, `execute`
- `script`, `javascript`, `onclick`, `onerror`, `alert`, `eval`

---

#### 8. **nginx-xss** - XSS Attack Detection
```ini
[nginx-xss]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 3        # Ban after 3 XSS attempts
bantime = 1209600   # 14 days
findtime = 600      # Within 10 minutes
```

**Detects XSS patterns**:
- `<script>` tags
- `javascript:` protocol
- `onerror=`, `onclick=` event handlers
- `alert()`, `eval()` function calls
- `vbscript:` protocol
- `onload=` event handler

---

#### 9. **nginx-rfi-lfi** - Remote/Local File Inclusion
```ini
[nginx-rfi-lfi]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 1        # Ban immediately (ZERO TOLERANCE)
bantime = 2592000   # 30 days (PERMANENT)
findtime = 300      # Within 5 minutes
```

**Detects file inclusion patterns**:
- `file://` protocol
- `../` and `..\\` path traversal
- `/etc/passwd` file access
- `/proc/self/` process access
- `ftp://`, `http://`, `https://` in file params
- `gopher://`, `data:` schemes

---

#### 10. **nginx-baduseragent** - Known Scanner Detection
```ini
[nginx-baduseragent]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 1        # Ban immediately
bantime = 1209600   # 14 days
findtime = 300      # Within 5 minutes
```

**Detects**:
- Known security scanners (Nikto, Nmap, Masscan)
- Exploitation frameworks (Metasploit)
- Vulnerability tools (SQLMap, Burp, ZAP)
- Archive utilities (curl, wget)

---

#### 11. **nginx-ddos** - DDoS Pattern Detection
```ini
[nginx-ddos]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 100      # Ban after 100 requests
bantime = 3600      # 1 hour
findtime = 60       # Within 1 minute
```

**Use case**: Detects 100+ requests/minute from single IP

---

### Editing Jail Configuration

To adjust thresholds and ban times:

```bash
# Edit Fail2Ban configuration
sudo nano /etc/fail2ban/jail.local

# Reload after changes
sudo systemctl reload fail2ban
```

**Common adjustments:**

```ini
# Make SQL injection ban permanent (365 days)
[nginx-sqli]
bantime = 31536000

# Make login rate limiting stricter
[nginx-login-limit]
maxretry = 2      # From 5 to 2 attempts

# Increase DDoS detection sensitivity
[nginx-ddos]
maxretry = 50     # From 100 to 50 requests/minute
```

## Rate Limiting

### Nginx Rate Limiting Zones

Rate limiting is configured in `/etc/nginx/sites-available/esc`:

```nginx
# Rate limiting zones
limit_req_zone $binary_remote_addr zone=general_limit:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=30r/m;
limit_req_zone $binary_remote_addr zone=login_limit:10m rate=5r/m;
limit_req_status 429;
```

### Zone Details

| Zone | Limit | Burst | Endpoints | Violation |
|------|-------|-------|-----------|-----------|
| `general_limit` | 10 req/s | 20 | All | 429 → Rate limit jail |
| `api_limit` | 30 req/min | 5 | `/api/*` | 429 → Rate limit jail |
| `login_limit` | 5 req/min | 2 | `/account/*`, `/auth/*`, `/login/*`, `/signin/*` | 429 → Rate limit jail + Fail2Ban |

### How It Works

1. **User makes request** → Nginx checks zone
2. **Limit exceeded** → Nginx returns `429 Too Many Requests`
3. **Fail2Ban detects** `429` response
4. **After 3 violations** → IP is banned for 24 hours
5. **Ban recorded** → `/var/log/fail2ban-custom.log`

### Adjusting Rate Limits

To change rate limits:

```bash
# Edit Nginx config
sudo nano /etc/nginx/sites-available/esc

# Find rate limiting zones section and adjust:
limit_req_zone $binary_remote_addr zone=general_limit:10m rate=20r/s;  # Increase to 20 req/s
limit_req_zone $binary_remote_addr zone=login_limit:10m rate=10r/m;   # Increase to 10 req/min

# Test configuration
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx
```

## Monitoring & Logging

### Real-Time Security Dashboard

View all security metrics in real-time:

```bash
/opt/bin/f2b-dashboard.sh
```

**Output shows:**
- Per-jail banned IP counts
- Recently banned IPs with timestamps
- Top 10 offending IPs
- Ban activity timeline

### Log Files

#### 1. Custom Ban Log (Human-Readable)
```bash
tail -f /var/log/fail2ban-custom.log

# Output:
# [2026-01-18 10:13:29] BANNED: 203.0.113.50 by nginx-sqli (Reason: SQL injection attempt)
# [2026-01-18 10:15:42] BANNED: 198.51.100.25 by nginx-scan (Reason: Directory enumeration)
# [2026-01-18 10:20:05] UNBANNED: 203.0.113.50 by manual
```

#### 2. Fail2Ban Decision Log
```bash
tail -f /var/log/fail2ban.log

# Output:
# 2026-01-18 10:13:29,123 fail2ban.filter [26451]: INFO [nginx-sqli] Found 203.0.113.50
# 2026-01-18 10:13:30,456 fail2ban.filter [26451]: INFO [nginx-sqli] 1 attempts in last 5 minutes
# 2026-01-18 10:13:31,789 fail2ban.actions [26451]: NOTICE [nginx-sqli] Ban 203.0.113.50
```

#### 3. Nginx Error Log
```bash
tail -f /var/log/nginx/esc_error.log

# Output:
# 2026-01-18 10:13:29 [error] 12345#12345: *1 [client 203.0.113.50] request forbidden - Invalid HTTP_HOST header
```

#### 4. Nginx Access Log
```bash
tail -f /var/log/nginx/esc_access.log

# Output:
# 203.0.113.50 - - [18/Jan/2026:10:13:29] "GET /admin/config.php HTTP/1.1" 403 143
# 203.0.113.50 - - [18/Jan/2026:10:13:31] "GET /wp-admin/ HTTP/1.1" 403 143
```

### Monitoring Commands

```bash
# Watch custom bans in real-time
watch tail -n 20 /var/log/fail2ban-custom.log

# Count banned IPs per jail
for jail in sshd nginx-cloudflare-only nginx-rate-limit nginx-noscript nginx-scan; do
  echo "$jail: $(fail2ban-client status $jail | grep 'Currently banned' | grep -oP '\d+(?=\s)' | tail -1)"
done

# Find most-banned IP
tail -f /var/log/fail2ban-custom.log | grep BANNED | awk '{print $5}' | sort | uniq -c | sort -rn | head -5

# Get ban statistics
echo "Ban statistics:"
grep "BANNED" /var/log/fail2ban-custom.log | wc -l | xargs echo "Total bans:"
grep "UNBANNED" /var/log/fail2ban-custom.log | wc -l | xargs echo "Total unbans:"
```

## Management Commands

### View Security Status

```bash
# Real-time dashboard
/opt/bin/f2b-dashboard.sh

# Or from app directory
cd /opt/apps/esc
./security.sh
```

### Check Specific Jail Status

```bash
# Show detailed jail info
sudo fail2ban-client status nginx-sqli

# Output:
# Status for the jail: nginx-sqli
# ├─ Filter
# │  ├─ Currently failed: 2
# │  ├─ Total failed: 156
# │  └─ Journal matches: 0
# ├─ Actions
# │  ├─ Currently banned: 5
# │  ├─ Total banned: 47
# │  └─ Banned IP list: 203.0.113.50 198.51.100.25 192.0.2.30 ...
```

### List All Currently Banned IPs

```bash
# Via iptables
iptables -L -n | grep DROP | awk '{print $10}' | sort -u

# Via Fail2Ban (all jails)
for jail in sshd nginx-cloudflare-only nginx-bad-requests nginx-rate-limit nginx-noscript nginx-scan nginx-sqli nginx-xss nginx-rfi-lfi nginx-baduseragent nginx-ddos; do
  echo "=== $jail ===" 
  sudo fail2ban-client status $jail | grep "Banned IP"
done

# Count total banned IPs
iptables -L -n | grep DROP | wc -l | xargs echo "Total banned IPs:"
```

### Unban an IP

**Emergency unban** (from all jails):

```bash
/opt/bin/f2b-unban.sh 203.0.113.50

# Or manually from specific jail:
sudo fail2ban-client set nginx-cloudflare-only unbanip 203.0.113.50
```

### Whitelist an IP (Prevent Future Bans)

For ISPs, proxies, or VPNs that need access:

```bash
# Edit Fail2Ban config
sudo nano /etc/fail2ban/jail.local

# Add to [DEFAULT] section:
ignoreip = 127.0.0.1 ::1 203.0.113.50

# Or append multiple IPs:
ignoreip = 127.0.0.1 ::1 203.0.113.0/24

# Reload
sudo systemctl reload fail2ban
```

### View Failed Login Attempts

```bash
# SSH failures
grep "Failed password" /var/log/auth.log | tail -20

# Failed login patterns
grep "invalid user\|Failed password" /var/log/auth.log | wc -l | xargs echo "Failed SSH attempts:"
```

## Emergency Procedures

### Server Under DDoS Attack

**Immediate response:**

```bash
1. Check dashboard
/opt/bin/f2b-dashboard.sh

2. View real-time bans
tail -f /var/log/fail2ban-custom.log

3. Check attack source
grep "BANNED" /var/log/fail2ban-custom.log | head -20 | awk '{print $5}' | sort | uniq -c | sort -rn

4. Identify attack pattern
tail -f /var/log/nginx/esc_access.log | grep "429"

5. Temporarily increase ban times
sudo nano /etc/fail2ban/jail.local
# Change all bantime = 3600 to bantime = 86400 (24 hours)
sudo systemctl reload fail2ban

6. Check Cloudflare
Log in to dashboard → Security → Activity log
Look for spike in requests from specific countries/IPs

7. Add Cloudflare firewall rule
Cloudflare → Security → WAF Rules → Add custom rule
Block traffic from attacking countries/regions (if identified)

8. Monitor closely
watch tail -n 30 /var/log/fail2ban-custom.log
```

### Restore Banned IP (Legitimate User Locked Out)

```bash
1. Verify IP is legitimate
/opt/bin/f2b-dashboard.sh

2. Check which jail banned it
grep "BANNED.*<IP>" /var/log/fail2ban-custom.log

3. Unban immediately
/opt/bin/f2b-unban.sh <IP>

4. (Optional) Whitelist to prevent future bans
sudo nano /etc/fail2ban/jail.local
# Add IP to ignoreip list
sudo systemctl reload fail2ban

5. Verify unban worked
sudo fail2ban-client status <JAIL>
# Check "Banned IP list" - IP should not appear
```

### Disable Fail2Ban (Emergency Only)

**Only do this if Fail2Ban is misconfigured and blocking all traffic:**

```bash
# Stop Fail2Ban
sudo systemctl stop fail2ban

# Disable on boot
sudo systemctl disable fail2ban

# Check iptables rules
iptables -L -n

# Remove Fail2Ban chains (if needed)
sudo iptables -F fail2ban-sshd
sudo iptables -F fail2ban-nginx-cloudflare-only
# ... (repeat for all chains)

# Save iptables changes
sudo iptables-save > /etc/iptables/rules.v4

# Re-enable when fixed
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

### Complete Lockdown (Nuclear Option)

```bash
# Block everything except your IP
sudo ufw reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from YOUR_IP to any port 22
sudo ufw allow from 173.245.48.0/20   # Cloudflare IPs
sudo ufw allow from 103.21.244.0/22   # Cloudflare IPs
# ... add all Cloudflare IP ranges
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable

# Re-enable selective access gradually
sudo ufw delete allow from 203.0.113.50 port 22
```

## Troubleshooting

### Fail2Ban Not Banning IPs

**Diagnose:**

```bash
1. Check if Fail2Ban is running
sudo systemctl status fail2ban

2. Check if jails are enabled
sudo fail2ban-client status

3. Check if filters are loaded
ls -la /etc/fail2ban/filter.d/

4. Check logs for errors
tail -f /var/log/fail2ban.log

5. Manually test a jail
sudo fail2ban-client set nginx-sqli banip 203.0.113.50

6. Check if ban applied
iptables -L -n | grep 203.0.113.50
```

### False Positives (Legitimate Users Banned)

**Solution:**

```bash
1. Unban user
/opt/bin/f2b-unban.sh <IP>

2. Whitelist IP (if recurring)
sudo nano /etc/fail2ban/jail.local
# Add: ignoreip = 127.0.0.1 ::1 <IP>
sudo systemctl reload fail2ban

3. Check jail thresholds
sudo fail2ban-client status <JAIL> | grep "maxretry"

4. Adjust if too strict
sudo nano /etc/fail2ban/jail.local
# Increase maxretry value
sudo systemctl reload fail2ban
```

### Logs Not Being Generated

**Check:**

```bash
# Check Nginx logging
ls -la /var/log/nginx/

# Check permissions
sudo chmod 644 /var/log/nginx/esc_access.log
sudo chmod 644 /var/log/nginx/esc_error.log

# Check Docker log output
docker compose -f compose.prod.yaml logs web

# Restart services
sudo systemctl restart nginx
docker compose -f compose.prod.yaml restart web
```

## Advanced Configuration

### Custom Filter Rules

Add custom detection patterns in `/etc/fail2ban/filter.d/`:

```bash
# Create custom filter
sudo nano /etc/fail2ban/filter.d/nginx-custom.conf

# Add pattern:
[Definition]
failregex = ^<HOST> .* "(?:.*your-pattern.*)" .*$
ignoreregex =
```

### Custom Actions

Execute custom actions on bans:

```bash
# Create custom action
sudo nano /etc/fail2ban/action.d/custom-action.conf

[Definition]
actionstart = echo "Custom action started" >> /var/log/custom.log
actionban = echo "Banned: <ip>" >> /var/log/custom.log
actionunban = echo "Unbanned: <ip>" >> /var/log/custom.log
```

### Performance Tuning

For high-traffic applications:

```bash
# Edit jail.local
sudo nano /etc/fail2ban/jail.local

# Increase memory usage for better performance
bantime = 86400       # 24 hours (fewer re-evaluations)
findtime = 3600       # 1 hour (broader detection window)

# Reload
sudo systemctl reload fail2ban
```

### Integration with External Services

#### Email Alerts

Enable email notifications on bans:

```bash
sudo nano /etc/fail2ban/jail.local

# Update in [DEFAULT] section:
destemail = your-email@example.com
sendername = Fail2Ban
action = %(action_mwl)s     # mail with log

# Requires working mail service
sudo apt install mailutils
```

---

**Last Updated**: January 2026  
**Version**: 1.0  
**Security Level**: Enterprise Grade
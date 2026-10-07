# ESC Platform: Production Deployment & Orchestration

> **Stack**: Docker Compose v2 | **Edge Proxy**: Traefik v3.6.12 | **Frontend**: SvelteKit 5 | **Backend**: Django 5.2.17 / Daphne | **Database**: PostgreSQL 17 | **Cache**: Redis 8

Production deployment repository for the **ESC Platform**, providing containerized multi-service orchestration, zero-downtime deployments, dual-router fallback routing, automated database backups, and edge TLS security.

---

## 📋 Table of Contents

- [System Architecture](#-system-architecture)
- [Traefik Routing & Dual-Router Rollback](#-traefik-routing--dual-router-rollback)
- [Service Stack Inventory](#-service-stack-inventory)
- [Storage & Backup Strategy](#-storage--backup-strategy)
- [SSL/TLS Management](#-ssltls-management)
- [Quick Deployment](#-quick-deployment)
- [Environment Configuration](#-environment-configuration)
- [Operations & Monitoring](#-operations--monitoring)
- [Security Hardening](#-security-hardening)

---

## 🏗 System Architecture

```text
                                Internet
                                   │
                                   ▼
             Cloudflare Edge (WAF, CDN, DDoS Protection, Origin SSL)
                                   │
                                   ▼
              Traefik v3.6.12 Reverse Proxy (Ports 80 / 443)
              - Automatic TLS & Cloudflare Origin CA Certs
              - Trusted Cloudflare Real-IP Restoration
              - Security Headers & Dynamic Rate Limiting
                                   │
         ┌─────────────────────────┼─────────────────────────┐
         │ (Priority 100)          │ (Priority 50)           │ (Priority 10)
         ▼                         ▼                         ▼
   Django Backend            SvelteKit 5 SSR           Django Fallback
   APIs, Admin, Media        Headless Frontend         Catch-all Router
   /api/*, /e/api/*, /admin  (Node.js Port 3000)       (Legacy Template Mode)
   (Daphne Port 8000)
         │                         │
         └────────────┬────────────┘
                      │
    ┌─────────────────┼─────────────────┐
    │                 │                 │
    ▼                 ▼                 ▼
PostgreSQL 17      Redis 8.0         Celery 5.6
Primary DB         Cache & Broker    Worker & Beat
```

---

## 🚦 Traefik Routing & Dual-Router Rollback

The production Traefik configuration implements three distinct priority routers to guarantee zero downtime and graceful rollbacks:

1. **Backend High-Priority Router (Priority 100)**:
   Routes all API endpoints, admin panels, static assets, and media directly to Django Daphne:
   - API endpoints: `/api/*`, `/e/api/*`, `/posts/api/*`, `/pages/api/*`, `/account/api/*`
   - Admin & operational portals: `/admin/*`, `/daddy/*`, `/billing/*`, `/analytics/*`, `/silk/*`
   - System assets: `/static/*`, `/media/*`, `/health/*`, `robots.txt`, `sitemap*.xml`
2. **Headless Frontend Router (Priority 50)**:
   Routes all standard browser traffic to the SvelteKit Node.js SSR container on port 3000.
3. **Django Fallback Router (Priority 10)**:
   If the frontend container is stopped or scaled down during maintenance, Traefik immediately falls back to routing traffic to Django's built-in server-rendered templates without returning 502 Bad Gateway errors.

---

## 📦 Service Stack Inventory

| Service | Image | Replicas | Role & Ports |
| :--- | :--- | :--- | :--- |
| **`traefik`** | `traefik:v3.6.12` | 1 | Edge reverse proxy, SSL termination (80, 443) |
| **`frontend`** | `andreastuko/esc-frontend:latest` | 1 | Headless SvelteKit SSR application (3000 internal) |
| **`web`** | `andreastuko/esc:latest` | 2 | Django ASGI Daphne application (8000 internal) |
| **`migrator`** | `andreastuko/esc:latest` | 1 (one-shot) | Database migration runner (`migrate` on primary & analytics DBs) |
| **`celery_worker`** | `andreastuko/esc:latest` | 1 | Asynchronous task processor (GeoIP, thumbnails, notifications) |
| **`celery_beat`** | `andreastuko/esc:latest` | 1 | Periodic task scheduler (backups, subscriptions, cleanups) |
| **`postgres`** | `postgres:17-alpine` | 1 | Primary relational database storage |
| **`redis`** | `redis:8-alpine` | 1 | In-memory key-value cache and Celery message broker |
| **`watchtower`** | `nickfedor/watchtower:1` | 1 | Automated image updates with rolling restarts |

---

## 💾 Storage & Backup Strategy

### Cloudflare R2 Multi-Bucket Separation

Static files and media assets are partitioned into distinct Cloudflare R2 buckets for strict permission scoping:

- **Private Bucket (`CLOUDFLARE_R2_PRIVATE_BUCKET`)**: Stores sensitive escort ID cards and selfie verification files with restricted access.
- **Static Bucket (`CLOUDFLARE_R2_PUBLIC_STATIC_BUCKET`)**: Serves immutable frontend and backend assets over a custom domain CDN.
- **Media Bucket (`CLOUDFLARE_R2_PUBLIC_MEDIA_BUCKET`)**: Serves public escort gallery photographs and promotional videos.

### Dual-Target Automated Database Backups

The Celery Beat scheduler triggers regular database backups streaming compressed dumps across two independent targets:

1. **Cloudflare R2**: Primary backup storage bucket.
2. **Backblaze B2**: Independent cold backup destination for catastrophe redundancy.

---

## 🔒 SSL/TLS Management

The platform supports two TLS certificate strategies:

### 1. Cloudflare Origin CA (Default & Recommended)

During deployment, the script automatically contacts the Cloudflare Origin CA API (`POST /certificates`) to generate high-security 15-year origin certificates. Traefik mounts these certificates dynamically from `./certs/` and reloads them without dropping active connections.

Utility commands:

```bash
./ssl.sh status      # Inspect certificate expiration and active domain coverage
./ssl.sh renew       # Force certificate regeneration via Cloudflare Origin API
```

### 2. Let's Encrypt ACME

Traefik also supports automatic TLS issuance via Let's Encrypt HTTP-01 challenge if Cloudflare API keys are not provided.

---

## 🚀 Quick Deployment

### Automated One-Command Deploy

Run the automated deployment script on an Ubuntu or Debian host:

```bash
chmod +x deploy.sh
./deploy.sh
```

The script autonomously handles:

1. Validating operating system and sudo privileges.
2. Removing any conflicting host web servers (e.g. host Nginx or Apache binding port 80).
3. Installing Docker and Docker Compose if missing.
4. Setting up persistent Fail2Ban SSH jail rules (3 retries leading to 30-day bans).
5. Configuring Cloudflare Origin CA certificates or Let's Encrypt ACME.
6. Syncing domain names and environment variables across `.env.docker`.
7. Pulling images, executing schema migrations via `migrator`, and starting services.

### Manual Launch

```bash
# 1. Prepare environment configuration
cp .env.example .env.docker
nano .env.docker

# 2. Pull latest container images
docker pull andreastuko/esc:latest
docker pull andreastuko/esc-frontend:latest

# 3. Start services in detached mode
docker compose -f compose.prod.yaml up -d
```

---

## ⚙️ Environment Configuration

Key configuration parameters required in `.env.docker`:

```env
# Domain & Edge Settings
DOMAIN_NAME=yourdomain.com
ENVIRONMENT=production
DEBUG=False
SECRET_KEY=your-secure-django-secret-key

# Database & Cache
POSTGRES_USER=esc_user
POSTGRES_PASSWORD=your-postgres-password
POSTGRES_DB=esc_db
DATABASE_URL=postgresql://esc_user:your-postgres-password@postgres:5432/esc_db
REDIS_URL=redis://redis:6379/0

# Cloudflare Origin CA & Edge Tokens
CLOUDFLARE_API_TOKEN=your-cloudflare-api-token
CLOUDFLARE_ORIGIN_CA_KEY=your-origin-ca-user-key

# Cloudflare R2 Storage Buckets
CLOUDFLARE_R2_PRIVATE_BUCKET=your-private-bucket
CLOUDFLARE_R2_PRIVATE_ACCESS_KEY=your-private-key
CLOUDFLARE_R2_PRIVATE_SECRET_KEY=your-private-secret

CLOUDFLARE_R2_PUBLIC_STATIC_BUCKET=your-static-bucket
CLOUDFLARE_R2_PUBLIC_STATIC_CUSTOM_DOMAIN=static.yourdomain.com

CLOUDFLARE_R2_PUBLIC_MEDIA_BUCKET=your-media-bucket
CLOUDFLARE_R2_PUBLIC_MEDIA_CUSTOM_DOMAIN=media.yourdomain.com

# Dual Backup Credentials
BACKUP_R2_BUCKET_NAME=your-backup-bucket
BACKUP_R2_ACCESS_KEY_ID=your-backup-access-key
BACKUP_R2_SECRET_ACCESS_KEY=your-backup-secret-key
```

---

## 📊 Operations & Monitoring

### Container Status & Logs

```bash
# View active service statuses
docker compose -f compose.prod.yaml ps

# Stream unified logs
docker compose -f compose.prod.yaml logs -f

# Inspect specific service logs
docker compose -f compose.prod.yaml logs -f frontend
docker compose -f compose.prod.yaml logs -f web
docker compose -f compose.prod.yaml logs -f celery_worker
docker compose -f compose.prod.yaml logs -f traefik
```

### Performing Database Migrations Manually

Migrations run automatically via the `migrator` service during startup. To run them on demand:

```bash
docker compose -f compose.prod.yaml run --rm migrator
```

### Rolling Updates

Watchtower automatically tracks registry updates for `andreastuko/esc:latest` and `andreastuko/esc-frontend:latest`. To update manually without downtime:

```bash
docker pull andreastuko/esc:latest
docker pull andreastuko/esc-frontend:latest
docker compose -f compose.prod.yaml up -d --no-deps web frontend
```

---

## 🛡 Security Hardening

- **No Root Privileges**: Application containers execute as non-root unprivileged users.
- **Fail2Ban Jail**: Custom SSH protection jail banning abusive IPs for 30 days after 3 failed attempts.
- **iptables Block Survival**: Banned IPs persist across host server reboots.
- **Traefik Security Headers**: HSTS enabled with `preload`, `nosniff`, `SAMEORIGIN`, and strict referrer policies.
- **Rate Limiting**: Configured at reverse proxy edge (30 avg / 20 burst per minute).

# Production Troubleshooting Guide: ESC Platform

This guide outlines diagnostic procedures, error codes, and operational fixes for common deployment, networking, and runtime issues.

---

## 📋 Quick Diagnostic Commands

Run these first on your VPS when diagnosing platform health:

```bash
# Check status of all containers
docker compose -f compose.prod.yaml ps
# Or for Dokploy:
docker compose -f compose.dokploy.yaml ps

# Inspect kernel Out-Of-Memory (OOM) events
dmesg -T | grep -i -E "oom|killed process"

# Check server memory and swap utilization
free -h

# Check available disk space
df -h /

# View real-time logs from a specific service
docker compose -f compose.prod.yaml logs -f --tail=100 web
docker compose -f compose.prod.yaml logs -f --tail=100 frontend
docker compose -f compose.prod.yaml logs -f --tail=100 migrator
docker compose -f compose.prod.yaml logs -f --tail=100 traefik
```

---

## 1. Health Check Failures & SSL Redirect Loops

### Symptoms

- The `web` service status oscillates between `starting` and `unhealthy`.
- Traefik returns `503 Service Unavailable` or `502 Bad Gateway`.
- Application logs show `301 Moved Permanently` on health check requests.

### Root Cause

Django's `SECURE_SSL_REDIRECT = True` redirects plaintext HTTP requests to HTTPS. When Docker internal health checks probe `http://127.0.0.1:8000/health/ready/` across the internal bridge network without SSL headers, Django issues a 301 redirect. Docker interprets redirects as check failures.

### Solution

1. **SSL Redirect Exemption**: The SSL redirect middleware explicitly exempts `/health/live/` and `/health/ready/`.
2. **Forwarded Protocol Header**: Docker health check scripts (`docker-health-check.py`) send `X-Forwarded-Proto: https` with `Host: localhost`.
3. **Traefik Health Check Hostname**: Ensure Traefik's load balancer health check configuration specifies `hostname=localhost`:

   ```yaml
   traefik.http.services.django-service.loadbalancer.healthcheck.hostname: localhost
   traefik.http.services.django-service.loadbalancer.healthcheck.path: /health/ready/
   ```

4. **Manual Test from Host**:

   ```bash
   docker exec -it $(docker ps -qf name=web | head -n 1) python3 ./docker-health-check.py
   ```

---

## 2. Low-Memory VPS (2.5 GB) Out-Of-Memory (OOM) Kills

### Symptoms

- Containers terminate unexpectedly with exit code `137` (`SIGKILL`).
- `dmesg -T` outputs `Out of memory: Killed process (python3)` or `(node)`.
- Services restart continuously during image updates or traffic bursts.

### Root Cause

Unconstrained memory usage during concurrent tasks (e.g. database migrations, SvelteKit SSR loads, Celery image resizing) exceeds host RAM.

### Solution

#### Step 1: Configure a Host Swapfile

On any VPS with 4GB RAM or less, enable a 2GB to 4GB swapfile:

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

#### Step 2: Enforce Tuned Resource Limits

Ensure `.env.docker` includes the low-memory limits configured for `compose.dokploy.yaml`:

```env
WEB_REPLICAS=2
POSTGRES_MEM_LIMIT=320M
REDIS_MEM_LIMIT=192M
REDIS_MAXMEMORY=160mb
MIGRATOR_MEM_LIMIT=320M
WEB_MEM_LIMIT=384M
FRONTEND_MEM_LIMIT=256M
CELERY_WORKER_MEM_LIMIT=320M
CELERY_BEAT_MEM_LIMIT=320M
```

#### Step 3: Celery Memory Bounds

Celery worker is configured with recycling flags in compose to avoid Python process bloat:

- `--max-tasks-per-child=100`
- `--max-memory-per-child=200000` (200MB limit per fork)

---

## 3. Database Schema Migrations & Migrator Service

### Symptoms

- The `web` container refuses to start because migrations have not completed.
- Log message: `web waiting for service migrator to complete successfully`.

### Root Cause

The `migrator` service runs `python manage.py migrate` and `python manage.py migrate --database=analytics` prior to launching web instances. If a migration fails or is locked, `web` remains in standby.

### Solution

#### Step 1: Inspect Migrator Logs

```bash
docker compose -f compose.prod.yaml logs migrator
```

#### Step 2: Run Migrations Interactively

```bash
docker compose -f compose.prod.yaml run --rm migrator bash -c \
  "python manage.py showmigrations && python manage.py migrate && python manage.py migrate --database=analytics"
```

#### Step 3: Resolve Migration Deadlocks

If PostgreSQL holds an exclusive lock:

```bash
docker exec -it $(docker ps -qf name=postgres) psql -U $POSTGRES_USER -d $POSTGRES_DB -c \
  "SELECT pid, query, state, age(clock_timestamp(), query_start) FROM pg_stat_activity WHERE state != 'idle';"
```

---

## 4. Traefik Routing & Dual-Router Rollback

### Symptoms

- Standard web traffic renders legacy Django template views instead of the modern SvelteKit frontend.
- Traefik returns `404 Not Found` or `502 Bad Gateway`.

### Understanding the Router Priority Hierarchy

Traefik evaluates incoming requests using priority ordering:

1. **Priority 100 (`django-backend`)**: Captures `/api/*`, `/e/api/*`, `/admin/*`, `/static/*`, `/media/*`.
2. **Priority 50 (`frontend-router`)**: Captures all browser requests and directs them to the SvelteKit frontend container on port 3000.
3. **Priority 10 (`django-fallback`)**: Catch-all router directing traffic to Django's built-in views only if the frontend service is unavailable.

### Diagnostic Steps

1. **Verify Frontend Container Status**:

   ```bash
   docker ps -f name=frontend
   ```

2. **Test Frontend Health Endpoint Directly**:

   ```bash
   docker exec -it $(docker ps -qf name=frontend) wget -qO- http://127.0.0.1:3000/up
   ```

3. **Inspect Traefik Logs for Route Mappings**:

   ```bash
   docker compose -f compose.prod.yaml logs traefik | grep -i "router"
   ```

---

## 5. Cloudflare Origin CA & TLS Handshake Errors

### Symptoms

- Browser displays Cloudflare Error `525: SSL Handshake Failed` or `526: Invalid SSL Certificate`.

### Solution

1. **Check Certificate Expiry**:

   ```bash
   ./ssl.sh status
   ```

2. **Force Certificate Renewal via Cloudflare Origin API**:

   ```bash
   ./ssl.sh renew
   ```

3. **Verify File Permissions on Mounted Certs**:
   Ensure `./certs/cert.pem` and `./certs/key.pem` are readable:

   ```bash
   chmod 644 ./certs/cert.pem
   chmod 600 ./certs/key.pem
   ```

4. **Cloudflare Dashboard SSL Mode**:
   Set SSL/TLS encryption mode to **Full (Strict)** in the Cloudflare dashboard.

---

## 6. M-Pesa Payment Callback Failures

### Symptoms

- Customer completes STK push on mobile handset, but account balance or subscription remains un-updated.

### Solution

1. **Verify Webhook Callback Secret**:
   Ensure `MPESA_CALLBACK_SECRET` in `.env.docker` is non-empty and matches the query token configured in the Safaricom portal:

   ```env
   MPESA_CALLBACK_SECRET=your-random-secret-token
   ```

2. **Check IP Allowlist**:
   If `MPESA_CALLBACK_IP_ALLOWLIST` is set, ensure it contains all Safaricom production IP addresses:

   ```env
   MPESA_CALLBACK_IP_ALLOWLIST=196.201.214.200,196.201.214.206,196.201.214.207,196.201.214.208
   ```

3. **Verify Reverse Proxy IP Trust**:
   Ensure `TRUSTED_PROXY_IPS` and `TRUST_CF_CONNECTING_IP=true` are active so client IPs are not masked as internal Docker gateway IPs (`172.x.x.x`).

---

## 7. Frontend SSR to Backend Communication

### Symptoms

- Frontend renders a 503 error page with "Backend Service Unavailable" and a retry button.
- Server logs show `FetchError: connect ECONNREFUSED http://web:8000`.

### Solution

1. **Check ALLOWED_HOSTS in Backend**:
   The Django backend must allow the Docker internal service name `web`:

   ```env
   ALLOWED_HOSTS=localhost,web,yourdomain.com,www.yourdomain.com
   ```

2. **Check Shared Docker Network**:
   Both `web` and `frontend` must belong to the same internal network (`internal-net` or `dokploy-network`).
3. **Check SSR Request Protocol Header**:
   Ensure SvelteKit SSR requests forward `X-Forwarded-Proto: https` to prevent internal 301 redirects.

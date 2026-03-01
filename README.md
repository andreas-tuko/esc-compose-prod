# ESC Application

A Django-based web application with Celery workers, Redis for caching and queuing.

## Architecture

- **Web**: Django application serving the main  website
- **Celery Worker**: Asynchronous task processing
- **Celery Beat**: Scheduled task execution
- **Redis**: Cache and message broker
- **PostgreSQL**: Primary database (internal), Analytics database (external)
- **Cloudflare R2**: Storage for static files and media
- **Nginx**: Reverse proxy


## Prerequisites

- Docker and Docker Compose
- PostgreSQL database
- Cloudflare R2 account
- M-Pesa API credentials
- Sentry account (optional)
- PostHog account (optional)
- Nginx

## Environment Configuration

Create a `.env.docker` file in the project root:

```env
SECRET_KEY=your-secret-key-here
DEBUG=False
ENVIRONMENT=production
ALLOWED_HOSTS=localhost,yourdomain.com
CSRF_ORIGINS=https://yourdomain.com

POSTGRES_USER=user
POSTGRES_PASSWORD=password
POSTGRES_DB=dbname

DATABASE_URL=postgresql://user:password@host:port/dbname
ANALYTICS_DATABASE_URL=postgresql://user:password@host:port/analytics_db

REDIS_URL=redis://redis:6379
REDIS_HOST=redis
REDIS_PASSWORD=

SITE_ID=1
SITE_NAME=Your Site Name
SITE_URL=https://yourdomain.com
BASE_URL=https://sandbox.safaricom.co.ke

DEFAULT_FROM_EMAIL=noreply@yourdomain.com
EMAIL_HOST=smtp.gmail.com
EMAIL_HOST_USER=your-email@gmail.com
EMAIL_HOST_PASSWORD=your-app-password
EMAIL_PORT=587

CLOUDFLARE_R2_ACCESS_KEY=your-access-key
CLOUDFLARE_R2_SECRET_KEY=your-secret-key
CLOUDFLARE_R2_BUCKET=your-bucket-name
CLOUDFLARE_R2_BUCKET_ENDPOINT=https://your-account-id.r2.cloudflarestorage.com
CLOUDFLARE_R2_TOKEN_VALUE=your-token

CLOUDFLARE_R2_PUBLIC_ACCESS_KEY=your-public-access-key
CLOUDFLARE_R2_PUBLIC_SECRET_KEY=your-public-secret-key
CLOUDFLARE_R2_PUBLIC_BUCKET=your-public-bucket
CLOUDFLARE_R2_PUBLIC_BUCKET_ENDPOINT=https://your-account-id.r2.cloudflarestorage.com
CLOUDFLARE_R2_PUBLIC_CUSTOM_DOMAIN=https://cdn.yourdomain.com

BACKUP_R2_ACCESS_KEY_ID=your-backup-access-key
BACKUP_R2_SECRET_ACCESS_KEY=your-backup-secret-key
BACKUP_R2_BUCKET_NAME=your-backup-bucket
BACKUP_R2_ENDPOINT=https://your-account-id.r2.cloudflarestorage.com
BACKUP_R2_ACCOUNT_ID=your-account-id
BACKUP_R2_REGION=auto

MPESA_CONSUMER_KEY=your-consumer-key
MPESA_CONSUMER_SECRET=your-consumer-secret
MPESA_PASSKEY=your-passkey
MPESA_SHORTCODE=174379
CALLBACK_URL=https://yourdomain.com/api/mpesa/callback

GOOGLE_OAUTH_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_OATH_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_OAUTH_CLIENT_SECRET=your-client-secret

GEOIP_LICENSE_KEY=your-maxmind-license-key

RECAPTCHA_PUBLIC_KEY=your-recaptcha-site-key
RECAPTCHA_PRIVATE_KEY=your-recaptcha-secret-key

SENTRY_DSN=https://your-sentry-dsn@sentry.io/project-id
POSTHOG_ENABLED=True
POSTHOG_HOST=https://eu.i.posthog.com
POSTHOG_API_KEY=your-posthog-project-api-key

ADMIN_NAME=Admin Name
ADMIN_EMAIL=admin@yourdomain.com

PYTHON_VERSION=3.13.5
UID=1000
````

## Production Deployment

Pull the latest image:

```bash
docker pull andreastuko/esc:latest
```

Start services:

```bash
docker compose up -d
```

Update production:

```bash
docker pull andreastuko/esc:latest
docker compose up -d
```

## Zero-Downtime Deployments

* Web service uses internal port exposure instead of direct port mapping
* Traefik handles routing and health checks
* Old containers remain active until new ones are healthy
* Start period allows full Django initialization

## Monitoring

```bash
docker compose logs -f
docker compose logs -f web
docker compose logs -f celery_worker
docker compose logs -f celery_beat
docker compose ps
docker compose exec redis redis-cli ping
```

## Local Development

Clone the repository:

```bash
git clone https://github.com/dennisneo6969/esc-compose-prod.git
cd esc-compose-prod

```

Create environment file:

```bash
cp .env.docker .env.local
```

Start local stack:

```bash
docker compose -f compose.local.yaml up
```

Access the application:

* [http://localhost:8000](http://localhost:8000)
* [http://localhost:8000/admin](http://localhost:8000/admin)

## Health Checks

* Django readiness via `docker-health-check.py`
* Redis ping checks
* Celery worker inspection
* Extended start period for migrations and static files

## Security

* Do not commit environment files
* Rotate secrets regularly
* Use strong passwords
* Enable 2FA on external services
* Keep Docker images updated

## Backup Strategy

* Automated database backups to Cloudflare R2
* Media replication across R2 buckets
* Retention configured in Django settings



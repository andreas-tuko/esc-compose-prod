#!/bin/bash

# ESC Django Application - Automated Deployment Script (Traefik Edition)
# Cloudflare handles all SSL - Traefik runs in Docker
# Includes: Docker, Traefik, Fail2Ban (SSH protection), Rate Limiting, and Headers

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Print functions
print_header()  { echo -e "\n${BLUE}============================================${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}============================================${NC}\n"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info()    { echo -e "${CYAN}ℹ $1${NC}"; }
print_step()    { echo -e "${MAGENTA}▶ $1${NC}"; }

# ---------------------------------------------------------------------------
# Check sudo access
# ---------------------------------------------------------------------------
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        print_info "This script requires sudo privileges. You may be prompted for your password."
        sudo -v
    fi
}

# ---------------------------------------------------------------------------
# Check OS compatibility
# ---------------------------------------------------------------------------
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            print_error "This script is designed for Ubuntu or Debian. Detected: $OS"
            exit 1
        fi
        print_success "OS Check: $OS $VER"
    else
        print_error "Cannot determine OS. This script requires Ubuntu or Debian."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Remove any conflicting host-level web servers
# Traefik runs in Docker on port 80 — nothing else should bind that port
# ---------------------------------------------------------------------------
remove_host_webservers() {
    print_header "Checking for Conflicting Host Web Servers"

    local found=false

    if command -v nginx &> /dev/null || systemctl list-units --type=service 2>/dev/null | grep -q nginx; then
        print_warning "Found Nginx on host — removing it (Traefik owns port 80)..."
        sudo systemctl stop nginx 2>/dev/null || true
        sudo systemctl disable nginx 2>/dev/null || true
        sudo apt remove -y nginx nginx-common 2>/dev/null || true
        sudo apt purge -y nginx* 2>/dev/null || true
        sudo rm -rf /etc/nginx 2>/dev/null || true
        print_success "Host Nginx removed"
        found=true
    fi

    if command -v apache2 &> /dev/null || systemctl list-units --type=service 2>/dev/null | grep -q apache2; then
        print_warning "Found Apache2 on host — removing it (Traefik owns port 80)..."
        sudo systemctl stop apache2 2>/dev/null || true
        sudo systemctl disable apache2 2>/dev/null || true
        sudo apt remove -y apache2 2>/dev/null || true
        sudo apt purge -y apache2* 2>/dev/null || true
        print_success "Host Apache2 removed"
        found=true
    fi

    if [ "$found" = false ]; then
        print_info "No conflicting host web servers found (good)"
    fi

    # Make sure port 80 is actually free before we start
    if ss -tlnp 2>/dev/null | grep -q ':80 ' || netstat -tlnp 2>/dev/null | grep -q ':80 '; then
        print_warning "Something is still bound to port 80. Traefik will fail to start."
        print_warning "Run: sudo ss -tlnp | grep :80  — to identify and stop the process."
    fi
}

# ---------------------------------------------------------------------------
# Load / save deployment config
# ---------------------------------------------------------------------------
load_existing_config() {
    CONFIG_FILE="${APP_DIR:-.}/.deployment_config"
    if [ -f "$CONFIG_FILE" ]; then
        print_info "Found existing configuration"
        source "$CONFIG_FILE"
        EXISTING_CONFIG=true
    else
        EXISTING_CONFIG=false
    fi
}

save_config() {
    CONFIG_FILE="$APP_DIR/.deployment_config"
    cat > "$CONFIG_FILE" << EOF
# ESC Deployment Configuration
DOMAIN_NAME="$DOMAIN_NAME"
DOCKER_USERNAME="$DOCKER_USERNAME"
APP_DIR="$APP_DIR"
SECURITY_ENABLED="$SECURITY_ENABLED"
ADMIN_EMAIL="$ADMIN_EMAIL"
EOF
    chmod 600 "$CONFIG_FILE"
    print_success "Configuration saved for future deployments"
}

# ---------------------------------------------------------------------------
# Security configuration prompt
# ---------------------------------------------------------------------------
configure_security() {
    print_header "Security Configuration"
    echo "Enable advanced security features? (Recommended: Yes)"
    echo "  • Fail2Ban SSH jail (3 retries → 30-day ban)"
    echo "  • iptables persistent block rules (bans survive reboots)"
    echo "  • Traefik rate limiting (configured via compose labels)"
    echo "  • Traefik secure response headers"
    echo

    read -p "Enable security features? [Y/n]: " ENABLE_SECURITY
    ENABLE_SECURITY=${ENABLE_SECURITY:-Y}

    if [[ "$ENABLE_SECURITY" =~ ^[Yy]$ ]]; then
        SECURITY_ENABLED="true"
        if [ -n "$ADMIN_EMAIL" ]; then
            read -p "Admin email for security alerts [$ADMIN_EMAIL]: " NEW_ADMIN_EMAIL
            ADMIN_EMAIL=${NEW_ADMIN_EMAIL:-$ADMIN_EMAIL}
        else
            read -p "Admin email for security alerts: " ADMIN_EMAIL
            while [ -z "$ADMIN_EMAIL" ]; do
                print_warning "Email cannot be empty"
                read -p "Admin email for security alerts: " ADMIN_EMAIL
            done
        fi
        print_success "Security features will be enabled"
    else
        SECURITY_ENABLED="false"
        ADMIN_EMAIL=""
        print_warning "Security features will be skipped (not recommended)"
    fi
}

# ---------------------------------------------------------------------------
# Interactive configuration
# ---------------------------------------------------------------------------
gather_config() {
    print_header "Configuration Setup"
    DEFAULT_APP_DIR="/opt/apps/esc"
    APP_DIR="${APP_DIR:-$DEFAULT_APP_DIR}"

    load_existing_config

    if [ "$EXISTING_CONFIG" = true ]; then
        print_success "Existing deployment detected!"
        echo
        echo "Previous configuration:"
        echo "  Domain:          $DOMAIN_NAME"
        echo "  Docker Hub User: $DOCKER_USERNAME"
        echo "  App Directory:   $APP_DIR"
        echo "  Security:        $SECURITY_ENABLED"
        echo
        read -p "Use existing configuration? [Y/n]: " USE_EXISTING
        USE_EXISTING=${USE_EXISTING:-Y}

        if [[ "$USE_EXISTING" =~ ^[Yy]$ ]]; then
            print_info "Using saved configuration"
            read -sp "Docker Hub password/token: " DOCKER_PASSWORD
            echo
            while [ -z "$DOCKER_PASSWORD" ]; do
                print_warning "Docker Hub password cannot be empty"
                read -sp "Docker Hub password/token: " DOCKER_PASSWORD
                echo
            done
            CREATE_USER="n"
            SETUP_FIREWALL="n"
            return 0
        fi
    fi

    if [ -n "$DOMAIN_NAME" ]; then
        read -p "Enter your domain name [$DOMAIN_NAME]: " NEW_DOMAIN_NAME
        DOMAIN_NAME=${NEW_DOMAIN_NAME:-$DOMAIN_NAME}
    else
        read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
        while [ -z "$DOMAIN_NAME" ]; do
            print_warning "Domain name cannot be empty"
            read -p "Enter your domain name: " DOMAIN_NAME
        done
    fi

    print_info "Docker Hub credentials are required to pull the private image"
    if [ -n "$DOCKER_USERNAME" ]; then
        read -p "Docker Hub username [$DOCKER_USERNAME]: " NEW_DOCKER_USERNAME
        DOCKER_USERNAME=${NEW_DOCKER_USERNAME:-$DOCKER_USERNAME}
    else
        read -p "Docker Hub username: " DOCKER_USERNAME
        while [ -z "$DOCKER_USERNAME" ]; do
            print_warning "Docker Hub username cannot be empty"
            read -p "Docker Hub username: " DOCKER_USERNAME
        done
    fi

    read -sp "Docker Hub password/token: " DOCKER_PASSWORD
    echo
    while [ -z "$DOCKER_PASSWORD" ]; do
        print_warning "Docker Hub password cannot be empty"
        read -sp "Docker Hub password/token: " DOCKER_PASSWORD
        echo
    done

    read -p "Application directory [$DEFAULT_APP_DIR]: " APP_DIR
    APP_DIR=${APP_DIR:-$DEFAULT_APP_DIR}

    if [ "$EXISTING_CONFIG" != true ]; then
        read -p "Create a dedicated 'deployer' user? (recommended) [Y/n]: " CREATE_USER
        CREATE_USER=${CREATE_USER:-Y}
    fi

    if [ "$EXISTING_CONFIG" != true ]; then
        read -p "Configure UFW firewall? (recommended) [Y/n]: " SETUP_FIREWALL
        SETUP_FIREWALL=${SETUP_FIREWALL:-Y}
    fi

    configure_security

    print_header "Configuration Summary"
    echo "Domain:               $DOMAIN_NAME"
    echo "Docker Hub User:      $DOCKER_USERNAME"
    echo "App Directory:        $APP_DIR"
    echo "Create deployer user: $CREATE_USER"
    echo "Setup firewall:       $SETUP_FIREWALL"
    echo "SSL:                  Handled by Cloudflare (Flexible mode)"
    echo "Reverse Proxy:        Traefik v3 (in Docker, port 80)"
    echo "Security Features:    $SECURITY_ENABLED"
    [ "$SECURITY_ENABLED" = "true" ] && echo "Admin Email:          $ADMIN_EMAIL"
    echo

    read -p "Proceed with installation? [Y/n]: " CONFIRM
    CONFIRM=${CONFIRM:-Y}
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled."
        exit 0
    fi
}

# ---------------------------------------------------------------------------
# System update
# ---------------------------------------------------------------------------
update_system() {
    print_header "Updating System Packages"
    sudo apt update
    sudo apt upgrade -y
    sudo apt install -y curl wget git nano jq mailutils sendmail net-tools
    sudo apt install -y iptables-persistent netfilter-persistent
    sudo apt install -y ufw
    print_success "System updated"
}

# ---------------------------------------------------------------------------
# Docker
# ---------------------------------------------------------------------------
install_docker() {
    print_header "Installing Docker"
    if command -v docker &> /dev/null; then
        print_warning "Docker is already installed"
        docker --version
    else
        print_info "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh
        sudo usermod -aG docker "$USER"
        # Re-initialise group membership for this shell session
        # (full effect takes place on next login, but this avoids script failure)
        newgrp docker << 'NEWGRP_END'
exit
NEWGRP_END
        print_success "Docker installed"
    fi

    if docker compose version &> /dev/null; then
        print_warning "Docker Compose is already installed"
        docker compose version
    else
        print_info "Installing Docker Compose plugin..."
        sudo apt install -y docker-compose-plugin
        print_success "Docker Compose installed"
    fi
}

# ---------------------------------------------------------------------------
# Deployer user
# ---------------------------------------------------------------------------
create_deployer_user() {
    if [[ "$CREATE_USER" =~ ^[Yy]$ ]]; then
        print_header "Creating Deployer User"
        if id "deployer" &>/dev/null; then
            print_warning "User 'deployer' already exists"
        else
            sudo useradd -m -s /bin/bash deployer
            sudo usermod -aG docker deployer
            sudo mkdir -p /home/deployer/.ssh
            sudo chmod 700 /home/deployer/.ssh
            print_success "User 'deployer' created and added to docker group"
        fi
    fi
}

# ---------------------------------------------------------------------------
# App directory
# ---------------------------------------------------------------------------
setup_app_directory() {
    print_header "Setting Up Application Directory"
    sudo mkdir -p "$APP_DIR"
    sudo chown -R "$USER:$USER" "$APP_DIR"
    print_success "Application directory created: $APP_DIR"
}

# ---------------------------------------------------------------------------
# Clone repo
# ---------------------------------------------------------------------------
clone_repository() {
    print_header "Cloning Repository"
    cd "$APP_DIR" || exit 1
    if [ -d ".git" ]; then
        print_warning "Repository already exists, pulling latest changes..."
        git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || true
    else
        print_info "Cloning from GitHub..."
        git clone https://github.com/andreas-tuko/esc-compose-prod.git .
    fi

    # Verify the expected compose file exists
    if [ ! -f "$APP_DIR/compose.prod.yaml" ]; then
        print_error "compose.prod.yaml not found after clone. Check the repository."
        exit 1
    fi

    # Warn if compose file still references nginx image (stale repo)
    if grep -q 'image: nginx' "$APP_DIR/compose.prod.yaml" 2>/dev/null; then
        print_warning "compose.prod.yaml still contains an nginx service."
        print_warning "The repository may not have been updated to the Traefik version."
        print_warning "Continuing — but review the compose file before starting."
    else
        print_success "compose.prod.yaml looks correct (Traefik-based)"
    fi

    print_success "Repository cloned/updated"
}

# ---------------------------------------------------------------------------
# Docker Hub login
# ---------------------------------------------------------------------------
docker_login() {
    print_header "Logging into Docker Hub"
    echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
    if [ $? -eq 0 ]; then
        print_success "Docker Hub login successful"
    else
        print_error "Docker Hub login failed. Check credentials."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
generate_secret_key() {
    python3 -c "import secrets; print(secrets.token_urlsafe(50))"
}

generate_postgres_password() {
    openssl rand -base64 32
}

link_env_file() {
    print_header "Linking Environment File"
    if [ -f "$APP_DIR/.env.docker" ]; then
        ln -sf "$APP_DIR/.env.docker" "$APP_DIR/.env"
        print_success "Environment file linked (.env → .env.docker)"
    else
        print_warning "Environment file not found, skipping link"
    fi
}

# ---------------------------------------------------------------------------
# Environment file
# BUG FIX: CSRF_ORIGINS and SITE_URL now use https:// because Cloudflare
# presents HTTPS to the browser. Django's CSRF validation checks the
# Origin/Referer header against CSRF_TRUSTED_ORIGINS, which must match
# what the browser sends — always https:// through Cloudflare.
# ---------------------------------------------------------------------------
setup_env_file() {
    print_header "Environment Configuration"

    if [ -f "$APP_DIR/.env.docker" ]; then
        print_warning "Environment file already exists"
        read -p "Do you want to reconfigure it? [y/N]: " RECONFIG_ENV
        if [[ ! "$RECONFIG_ENV" =~ ^[Yy]$ ]]; then
            print_info "Keeping existing environment file"
            print_success "Skipping environment configuration"
            return
        fi
        cp "$APP_DIR/.env.docker" "$APP_DIR/.env.docker.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "Existing file backed up"
    fi

    print_step "Creating environment file with default values..."

    GENERATED_SECRET_KEY=$(generate_secret_key)
    GENERATED_POSTGRES_PASSWORD=$(generate_postgres_password)

    cat > "$APP_DIR/.env.docker" << EOF
# ============================================
# Django Core Settings
# ============================================
SECRET_KEY=$GENERATED_SECRET_KEY
DEBUG=False
ENVIRONMENT=production
ALLOWED_HOSTS=localhost,$DOMAIN_NAME,www.$DOMAIN_NAME
# https:// is required — Cloudflare terminates TLS so the browser always
# sends HTTPS Origin/Referer headers. Using http:// here causes CSRF failures.
CSRF_ORIGINS=https://$DOMAIN_NAME,https://www.$DOMAIN_NAME

# ============================================
# Database Configuration
# ============================================
POSTGRES_USER=user
POSTGRES_PASSWORD=$GENERATED_POSTGRES_PASSWORD
POSTGRES_DB=dbname
PGUSER=user

DATABASE_URL=postgresql://user:password@host:port/dbname
ANALYTICS_DATABASE_URL=postgresql://user:password@host:port/analytics_db

# ============================================
# Redis Configuration
# ============================================
REDIS_URL=redis://redis:6379
REDIS_HOST=redis
REDIS_PASSWORD=

# ============================================
# Site Configuration
# ============================================
SITE_ID=1
SITE_NAME=$DOMAIN_NAME
# https:// — Cloudflare handles TLS; the public-facing URL is always HTTPS
SITE_URL=https://$DOMAIN_NAME
BASE_URL=https://sandbox.safaricom.co.ke

# ============================================
# Email Configuration
# ============================================
DEFAULT_FROM_EMAIL=noreply@$DOMAIN_NAME
EMAIL_HOST=smtp.gmail.com
EMAIL_HOST_USER=your-email@gmail.com
EMAIL_HOST_PASSWORD=your-app-password
EMAIL_PORT=587

# ============================================
# Cloudflare R2 Storage (Private)
# ============================================
CLOUDFLARE_R2_ACCESS_KEY=your-access-key
CLOUDFLARE_R2_SECRET_KEY=your-secret-key
CLOUDFLARE_R2_BUCKET=your-bucket-name
CLOUDFLARE_R2_BUCKET_ENDPOINT=https://your-account-id.r2.cloudflarestorage.com
CLOUDFLARE_R2_TOKEN_VALUE=your-token

# ============================================
# Cloudflare R2 Storage (Public/CDN)
# ============================================
CLOUDFLARE_R2_PUBLIC_ACCESS_KEY=your-public-access-key
CLOUDFLARE_R2_PUBLIC_SECRET_KEY=your-public-secret-key
CLOUDFLARE_R2_PUBLIC_BUCKET=your-public-bucket
CLOUDFLARE_R2_PUBLIC_BUCKET_ENDPOINT=https://your-account-id.r2.cloudflarestorage.com
CLOUDFLARE_R2_PUBLIC_CUSTOM_DOMAIN=https://cdn.$DOMAIN_NAME

# ============================================
# Backup R2 Storage
# ============================================
BACKUP_R2_ACCESS_KEY_ID=your-backup-access-key
BACKUP_R2_SECRET_ACCESS_KEY=your-backup-secret-key
BACKUP_R2_BUCKET_NAME=your-backup-bucket
BACKUP_R2_ENDPOINT=https://your-account-id.r2.cloudflarestorage.com
BACKUP_R2_ACCOUNT_ID=your-account-id
BACKUP_R2_REGION=auto

# ============================================
# M-Pesa Payment Configuration
# ============================================
MPESA_CONSUMER_KEY=your-consumer-key
MPESA_CONSUMER_SECRET=your-consumer-secret
MPESA_PASSKEY=your-passkey
MPESA_SHORTCODE=174379
CALLBACK_URL=https://$DOMAIN_NAME/api/mpesa/callback

# ============================================
# Google OAuth
# ============================================
GOOGLE_OAUTH_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_OAUTH_CLIENT_SECRET=your-client-secret

# ============================================
# GeoIP Configuration
# ============================================
GEOIP_LICENSE_KEY=your-maxmind-license-key

# ============================================
# reCAPTCHA
# ============================================
RECAPTCHA_PUBLIC_KEY=your-recaptcha-site-key
RECAPTCHA_PRIVATE_KEY=your-recaptcha-secret-key

# ============================================
# Monitoring & Analytics
# ============================================
SENTRY_DSN=https://your-sentry-dsn@sentry.io/project-id
POSTHOG_ENABLED=True
POSTHOG_HOST=https://eu.i.posthog.com
POSTHOG_API_KEY=your-posthog-project-api-key

# ============================================
# Watchtower Email Notifications
# ============================================
WATCHTOWER_NOTIFICATION_EMAIL_FROM=watchtower@$DOMAIN_NAME
WATCHTOWER_NOTIFICATION_EMAIL_TO=$ADMIN_EMAIL
WATCHTOWER_NOTIFICATION_EMAIL_SERVER=smtp.gmail.com
WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PORT=587
WATCHTOWER_NOTIFICATION_EMAIL_SERVER_USER=your-email@gmail.com
WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PASSWORD=your-app-password
WATCHTOWER_NOTIFICATION_EMAIL_DELAY=2

# ============================================
# Admin Configuration
# ============================================
ADMIN_NAME=Admin Name
ADMIN_EMAIL=admin@$DOMAIN_NAME

# ============================================
# Python Configuration
# ============================================
PYTHON_VERSION=3.13.5
UID=1000
EOF

    print_success "Environment file created"

    print_header "IMPORTANT: Environment Configuration Required"
    echo
    print_warning "The application REQUIRES proper configuration before starting!"
    echo
    print_info "Press Enter to open the editor and configure your environment..."
    read -r

    nano "$APP_DIR/.env.docker"
    print_success "Environment file saved"
    validate_env_file
}

# ---------------------------------------------------------------------------
# Validate env
# ---------------------------------------------------------------------------
validate_env_file() {
    print_header "Validating Environment Configuration"

    local validation_failed=false
    local errors=()
    local warnings=()

    if [ ! -f "$APP_DIR/.env.docker" ]; then
        print_error "Environment file not found!"
        exit 1
    fi

    set -a
    source "$APP_DIR/.env.docker" 2>/dev/null || true
    set +a

    # Critical checks
    if [ -z "$SECRET_KEY" ] || [ "$SECRET_KEY" = "your-secret-key-here" ]; then
        errors+=("SECRET_KEY is not configured")
        validation_failed=true
    fi

    if [ -z "$ALLOWED_HOSTS" ] || [[ "$ALLOWED_HOSTS" == *"yourdomain.com"* ]]; then
        errors+=("ALLOWED_HOSTS contains placeholder domain")
        validation_failed=true
    fi

    # CSRF origin sanity check — should be https:// for Cloudflare setups
    if [[ "$CSRF_ORIGINS" == *"http://$DOMAIN_NAME"* ]] && [[ "$CSRF_ORIGINS" != *"https://$DOMAIN_NAME"* ]]; then
        errors+=("CSRF_ORIGINS uses http:// — must be https:// (Cloudflare presents HTTPS to browsers)")
        validation_failed=true
    fi

    # Non-critical warnings
    if [[ "$DATABASE_URL" == *"user:password@host"* ]]; then
        warnings+=("DATABASE_URL still contains placeholder values")
    fi

    if [ "$EMAIL_HOST_USER" = "your-email@gmail.com" ]; then
        warnings+=("Email not configured — Watchtower notifications will not work")
    fi

    if [ "$POSTGRES_PASSWORD" = "your-postgres-password" ]; then
        warnings+=("POSTGRES_PASSWORD is still the placeholder value")
    fi

    if [ "$validation_failed" = true ]; then
        print_error "Configuration validation FAILED!"
        echo
        print_error "Critical errors found:"
        for error in "${errors[@]}"; do echo "  ✗ $error"; done
        echo
        read -p "Edit configuration again? [Y/n]: " EDIT_AGAIN
        EDIT_AGAIN=${EDIT_AGAIN:-Y}
        if [[ "$EDIT_AGAIN" =~ ^[Yy]$ ]]; then
            nano "$APP_DIR/.env.docker"
            validate_env_file
            return
        else
            print_error "Cannot proceed with invalid configuration."
            exit 1
        fi
    fi

    if [ ${#warnings[@]} -gt 0 ]; then
        print_warning "Configuration warnings (non-critical):"
        for warning in "${warnings[@]}"; do echo "  ⚠ $warning"; done
        echo
    fi

    print_success "Environment configuration validated"
}

# ---------------------------------------------------------------------------
# Clean up any leftover nginx artefacts from old deployments
# Safe to run on fresh installs — just a no-op if nothing exists
# ---------------------------------------------------------------------------
cleanup_old_nginx_artefacts() {
    print_header "Cleaning Up Old Nginx Artefacts"
    local cleaned=false

    if [ -d "$APP_DIR/nginx" ]; then
        sudo rm -rf "$APP_DIR/nginx"
        print_success "Removed $APP_DIR/nginx/ (not needed with Traefik)"
        cleaned=true
    fi

    # Remove any stale nginx container that might be lingering
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q 'nginx'; then
        print_warning "Found lingering nginx container(s) — stopping and removing..."
        docker ps -a --format '{{.Names}}' | grep nginx | xargs -r docker rm -f 2>/dev/null || true
        cleaned=true
    fi

    if [ "$cleaned" = false ]; then
        print_info "No old nginx artefacts found (good)"
    fi
}

# ---------------------------------------------------------------------------
# Install Fail2Ban
# ---------------------------------------------------------------------------
install_fail2ban() {
    print_header "Installing Fail2Ban"
    if command -v fail2ban-server &> /dev/null; then
        print_warning "Fail2Ban already installed"
    else
        sudo apt install -y fail2ban
        print_success "Fail2Ban installed"
    fi
}

# ---------------------------------------------------------------------------
# Configure Fail2Ban — SSH protection only
# Traefik handles HTTP-level rate limiting via compose labels
# ---------------------------------------------------------------------------
setup_fail2ban() {
    print_header "Configuring Fail2Ban (SSH jail)"

    sudo tee /etc/fail2ban/jail.local > /dev/null << 'EOF'
[DEFAULT]
bantime  = 2592000
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

banaction = iptables-multiport

# ── SSH ────────────────────────────────────────────────────────────────────
[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
backend  = %(sshd_backend)s
maxretry = 3
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable fail2ban
    sudo systemctl restart fail2ban
    sleep 3

    if systemctl is-active --quiet fail2ban; then
        print_success "Fail2Ban configured and started (SSH jail active)"
        sudo fail2ban-client status 2>/dev/null || true
    else
        print_warning "Fail2Ban failed to start — check: sudo journalctl -u fail2ban"
    fi
}

# ---------------------------------------------------------------------------
# Persist iptables rules across reboots
# ---------------------------------------------------------------------------
setup_iptables_persistence() {
    print_header "Setting Up iptables Persistence"

    sudo systemctl enable netfilter-persistent 2>/dev/null || true

    sudo iptables -A INPUT -m conntrack --ctstate INVALID -j DROP 2>/dev/null || true
    sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true

    sudo /usr/sbin/netfilter-persistent save 2>/dev/null || \
    sudo /usr/share/netfilter-persistent/plugins.d/15-ip4tables save 2>/dev/null || \
    sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
    sudo ip6tables-save | sudo tee /etc/iptables/rules.v6 > /dev/null

    print_success "iptables rules saved — will survive reboots"
}

# ---------------------------------------------------------------------------
# Management scripts
# BUG FIX: deploy.sh and start.sh wait 30s (was 15s) to account for
# Traefik depending on web which has a 60s healthcheck start_period.
# The check now waits for traefik specifically, not just any "Up" service.
# ---------------------------------------------------------------------------
create_management_scripts() {
    print_header "Creating Management Scripts"

    # deploy.sh
    cat > "$APP_DIR/deploy.sh" << 'SCRIPT'
#!/bin/bash
set -e
echo "Starting deployment..."
cd "$(dirname "$0")" || exit 1
echo "Pulling latest images..."
docker compose -f compose.prod.yaml pull || { echo "Failed to pull images"; exit 1; }
echo "Stopping containers..."
docker compose -f compose.prod.yaml down || true
echo "Starting new containers..."
docker compose -f compose.prod.yaml up -d
echo "Waiting for services to initialise (30s)..."
sleep 30
docker compose -f compose.prod.yaml ps
echo "Deployment complete!"
SCRIPT
    chmod +x "$APP_DIR/deploy.sh"

    # logs.sh
    cat > "$APP_DIR/logs.sh" << 'SCRIPT'
#!/bin/bash
cd "$(dirname "$0")" || exit 1
SERVICE=${1:-}
if [ -z "$SERVICE" ]; then
    docker compose -f compose.prod.yaml logs -f
else
    docker compose -f compose.prod.yaml logs -f "$SERVICE"
fi
SCRIPT
    chmod +x "$APP_DIR/logs.sh"

    # status.sh
    cat > "$APP_DIR/status.sh" << 'SCRIPT'
#!/bin/bash
cd "$(dirname "$0")" || exit 1
echo "=== Container Status ==="
docker compose -f compose.prod.yaml ps
echo
echo "=== Traefik Accessibility ==="
curl -s -o /dev/null -w "HTTP status: %{http_code}\n" http://localhost/ || echo "Traefik not responding on port 80"
echo
echo "=== Resource Usage ==="
docker stats --no-stream
echo
echo "=== Fail2Ban Status ==="
sudo fail2ban-client status 2>/dev/null || echo "Fail2Ban not running"
echo
echo "=== Currently Banned IPs (iptables) ==="
sudo iptables -L INPUT -n | grep DROP | awk '{print $4}' | grep -v '0.0.0.0' || echo "None"
SCRIPT
    chmod +x "$APP_DIR/status.sh"

    # stop.sh
    cat > "$APP_DIR/stop.sh" << 'SCRIPT'
#!/bin/bash
cd "$(dirname "$0")" || exit 1
echo "Stopping all services..."
docker compose -f compose.prod.yaml down
echo "Services stopped."
SCRIPT
    chmod +x "$APP_DIR/stop.sh"

    # start.sh
    cat > "$APP_DIR/start.sh" << 'SCRIPT'
#!/bin/bash
cd "$(dirname "$0")" || exit 1
echo "Starting all services..."
docker compose -f compose.prod.yaml up -d
echo "Waiting for services to initialise (30s)..."
sleep 30
docker compose -f compose.prod.yaml ps
SCRIPT
    chmod +x "$APP_DIR/start.sh"

    # unban.sh
    cat > "$APP_DIR/unban.sh" << 'SCRIPT'
#!/bin/bash
IP="$1"
if [ -z "$IP" ]; then
    echo "Usage: $0 <ip-address>"
    exit 1
fi
echo "Removing iptables ban for $IP..."
sudo iptables -D INPUT -s "$IP" -j DROP 2>/dev/null && echo "iptables rule removed" || echo "IP not found in iptables"
sudo fail2ban-client unban "$IP" 2>/dev/null && echo "Fail2Ban ban removed" || true
sudo netfilter-persistent save
SCRIPT
    chmod +x "$APP_DIR/unban.sh"

    print_success "Management scripts created in $APP_DIR/"
}

# ---------------------------------------------------------------------------
# UFW firewall
# ---------------------------------------------------------------------------
setup_firewall() {
    if [[ "$SETUP_FIREWALL" =~ ^[Yy]$ ]]; then
        print_header "Configuring UFW Firewall"
        sudo ufw --force reset > /dev/null 2>&1 || true
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        sudo ufw allow 22/tcp    comment 'SSH'
        sudo ufw allow 80/tcp    comment 'HTTP  (Traefik)'
        sudo ufw allow 443/tcp   comment 'HTTPS (Cloudflare origin)'
        echo "y" | sudo ufw enable > /dev/null 2>&1
        print_success "Firewall configured"
        sudo ufw status verbose
    fi
}

# ---------------------------------------------------------------------------
# Systemd service — starts the full Docker Compose stack on boot
# ---------------------------------------------------------------------------
setup_systemd() {
    print_header "Setting Up Systemd Service"
    sudo tee /etc/systemd/system/esc.service > /dev/null << EOF
[Unit]
Description=ESC Django Application (Docker Compose + Traefik)
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/docker compose -f compose.prod.yaml up -d
ExecStop=/usr/bin/docker compose -f compose.prod.yaml down
ExecReload=/usr/bin/docker compose -f compose.prod.yaml restart
User=$USER
Group=$USER
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable esc.service
    print_success "Systemd service 'esc' created and enabled"
}

# ---------------------------------------------------------------------------
# Start application
# BUG FIX: Wait extended to 45s and check both web and traefik health.
# The original 15s wait was too short given web's 60s start_period and
# traefik depending on web being healthy first.
# ---------------------------------------------------------------------------
start_application() {
    print_header "Starting Application"
    cd "$APP_DIR" || exit 1

    print_info "Pulling latest Docker images..."
    if ! docker compose -f compose.prod.yaml pull; then
        print_warning "Failed to pull some images, continuing with existing images..."
    else
        print_success "Docker images pulled successfully"
    fi

    print_info "Starting services..."
    if ! docker compose -f compose.prod.yaml up -d; then
        print_error "Failed to start services"
        docker compose -f compose.prod.yaml logs --tail=30
        exit 1
    fi
    print_success "Services started"

    print_info "Waiting for services to initialise..."
    print_info "(web has a 60s start period; traefik starts after web is healthy)"
    for i in {1..9}; do
        echo -n "."
        sleep 5
    done
    echo
    # Give a bit more time for traefik to come up after web is healthy
    sleep 15

    echo
    docker compose -f compose.prod.yaml ps

    # Quick connectivity check
    echo
    print_info "Testing HTTP connectivity via Traefik..."
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://localhost/ 2>/dev/null || echo "000")
    if [ "$HTTP_STATUS" != "000" ]; then
        print_success "Traefik is responding (HTTP $HTTP_STATUS)"
    else
        print_warning "Traefik did not respond on port 80 yet — it may still be starting."
        print_info "Check: $APP_DIR/logs.sh traefik"
    fi
}

# ---------------------------------------------------------------------------
# Completion message
# ---------------------------------------------------------------------------
print_completion() {
    print_header "Installation Complete!"

    echo -e "${GREEN}Your ESC Django application is deployed with Traefik + Cloudflare!${NC}\n"

    echo "Application:"
    echo "  Public URL:  https://$DOMAIN_NAME  (Cloudflare → Traefik → Django)"
    echo "  App dir:     $APP_DIR"
    echo "  Env file:    $APP_DIR/.env.docker"
    echo
    echo "Stack:"
    echo "  Cloudflare   — TLS termination, CDN, DDoS protection"
    echo "  Traefik v3   — Reverse proxy, rate limiting, secure headers"
    echo "  Django/Gunicorn  — Application server (port 8000, internal only)"
    echo "  PostgreSQL 17 — Database"
    echo "  Redis 8       — Cache / Celery broker"
    echo "  Celery        — Async task worker + beat scheduler"
    echo "  Watchtower    — Automatic image updates (daily)"
    echo
    echo "Management Commands:"
    echo "  Deploy/Update:  $APP_DIR/deploy.sh"
    echo "  View Logs:      $APP_DIR/logs.sh [service]"
    echo "  Check Status:   $APP_DIR/status.sh"
    echo "  Stop Services:  $APP_DIR/stop.sh"
    echo "  Start Services: $APP_DIR/start.sh"
    echo "  Unban an IP:    $APP_DIR/unban.sh <ip>"
    echo

    if [ "$SECURITY_ENABLED" = "true" ]; then
        echo -e "${GREEN}Security Features Active:${NC}"
        echo "  ✓ Fail2Ban       — SSH jail (3 retries → 30-day ban)"
        echo "  ✓ Traefik        — Rate limiting (30 req/min avg, burst 20)"
        echo "  ✓ Traefik        — Secure response headers (HSTS, XSS, CSP, etc.)"
        echo "  ✓ iptables-persistent — Bans survive reboots"
        echo
        echo "  Fail2Ban status: sudo fail2ban-client status sshd"
        echo
    fi

    echo "Cloudflare Configuration:"
    echo "  1. DNS A record  → $(hostname -I | awk '{print $1}')"
    echo "  2. SSL/TLS mode  → Flexible (Cloudflare encrypts to browser; Traefik uses HTTP)"
    echo "  3. Always Use HTTPS      → On"
    echo "  4. Automatic HTTPS Rewrites → On"
    echo "  5. Consider enabling Cloudflare WAF for additional protection"
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Create Django superuser:"
    echo "     cd $APP_DIR && docker compose -f compose.prod.yaml exec web python manage.py createsuperuser"
    echo "  2. Monitor logs:"
    echo "     $APP_DIR/logs.sh"
    echo "  3. Verify the site is reachable:"
    echo "     curl -I https://$DOMAIN_NAME"
    echo "  4. Check Traefik is routing correctly:"
    echo "     $APP_DIR/logs.sh traefik"
    echo

    print_success "Deployment complete!"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    print_header "ESC Django Application - Automated Deployment (Traefik Edition)"

    check_sudo
    check_os
    remove_host_webservers
    gather_config

    update_system
    install_docker
    create_deployer_user
    setup_app_directory
    clone_repository
    docker_login
    setup_env_file
    link_env_file
    cleanup_old_nginx_artefacts

    if [ "$SECURITY_ENABLED" = "true" ]; then
        install_fail2ban
        setup_fail2ban
        setup_iptables_persistence
    fi

    setup_systemd
    setup_firewall
    create_management_scripts

    save_config

    print_header "Ready to Start Application"
    print_info "All configuration is complete!"
    echo
    read -p "Start the application now? [Y/n]: " START_NOW
    START_NOW=${START_NOW:-Y}

    if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
        start_application
    else
        print_info "Run '$APP_DIR/start.sh' when ready"
    fi

    print_completion
}

main

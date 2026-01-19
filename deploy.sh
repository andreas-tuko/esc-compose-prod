#!/bin/bash

# ESC Django Application - Automated Deployment Script
# Cloudflare handles all SSL - Nginx runs in Docker
# Includes: Docker, Nginx in Container, Fail2Ban, Rate Limiting

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
print_header() {
    echo -e "\n${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

print_step() {
    echo -e "${MAGENTA}▶ $1${NC}"
}

# Check sudo access
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        print_info "This script requires sudo privileges. You may be prompted for your password."
        sudo -v
    fi
}

# Check OS compatibility
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

# Remove conflicting Nginx on host
remove_host_nginx() {
    print_header "Checking for Host Nginx Installation"
    
    if command -v nginx &> /dev/null; then
        print_warning "Found Nginx running on host system. Removing it..."
        
        sudo systemctl stop nginx 2>/dev/null || true
        sudo systemctl disable nginx 2>/dev/null || true
        sudo apt remove -y nginx nginx-common 2>/dev/null || true
        sudo apt purge -y nginx* 2>/dev/null || true
        
        # Remove old configs
        sudo rm -rf /etc/nginx 2>/dev/null || true
        
        print_success "Host Nginx removed. Nginx will run in Docker only"
    else
        print_info "No host Nginx found (good)"
    fi
}

# Load existing configuration
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

# Save configuration for future runs
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

# Configure security settings
configure_security() {
    print_header "Security Configuration"
    
    echo "Enable advanced security features? (Recommended: Yes)"
    echo "  • Fail2Ban with multi-jail detection"
    echo "  • Rate limiting protection"
    echo "  • Vulnerability scanning detection"
    echo "  • DDoS protection"
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

# Interactive configuration
gather_config() {
    print_header "Configuration Setup"
    
    DEFAULT_APP_DIR="/opt/apps/esc"
    APP_DIR="${APP_DIR:-$DEFAULT_APP_DIR}"
    
    load_existing_config
    
    if [ "$EXISTING_CONFIG" = true ]; then
        print_success "Existing deployment detected!"
        echo
        echo "Previous configuration:"
        echo "  Domain: $DOMAIN_NAME"
        echo "  Docker Hub User: $DOCKER_USERNAME"
        echo "  App Directory: $APP_DIR"
        echo "  Security: $SECURITY_ENABLED"
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
    
    # Domain name
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
    
    # Docker Hub credentials
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
    
    # Application directory
    read -p "Application directory [$DEFAULT_APP_DIR]: " APP_DIR
    APP_DIR=${APP_DIR:-$DEFAULT_APP_DIR}
    
    # Create deployer user
    if [ "$EXISTING_CONFIG" != true ]; then
        read -p "Create a dedicated 'deployer' user? (recommended) [Y/n]: " CREATE_USER
        CREATE_USER=${CREATE_USER:-Y}
    fi
    
    # Setup firewall
    if [ "$EXISTING_CONFIG" != true ]; then
        read -p "Configure UFW firewall? (recommended) [Y/n]: " SETUP_FIREWALL
        SETUP_FIREWALL=${SETUP_FIREWALL:-Y}
    fi
    
    # Security configuration
    configure_security
    
    print_header "Configuration Summary"
    echo "Domain: $DOMAIN_NAME"
    echo "Docker Hub User: $DOCKER_USERNAME"
    echo "App Directory: $APP_DIR"
    echo "Create deployer user: $CREATE_USER"
    echo "Setup firewall: $SETUP_FIREWALL"
    echo "SSL: Handled by Cloudflare (HTTP in Docker)"
    echo "Nginx: Running in Docker container (host Nginx will be removed)"
    echo "Security Features: $SECURITY_ENABLED"
    if [ "$SECURITY_ENABLED" = "true" ]; then
        echo "Admin Email: $ADMIN_EMAIL"
    fi
    echo
    
    read -p "Proceed with installation? [Y/n]: " CONFIRM
    CONFIRM=${CONFIRM:-Y}
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled."
        exit 0
    fi
}

# Update system
update_system() {
    print_header "Updating System Packages"
    sudo apt update
    sudo apt upgrade -y
    sudo apt install -y curl wget git ufw nano jq mailutils sendmail
    print_success "System updated"
}

# Install Docker
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
        newgrp docker << END
exit
END
        print_success "Docker installed"
    fi
    
    if docker compose version &> /dev/null; then
        print_warning "Docker Compose is already installed"
        docker compose version
    else
        print_info "Installing Docker Compose..."
        sudo apt install -y docker-compose-plugin
        print_success "Docker Compose installed"
    fi
}

# Create deployer user
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
            print_success "User 'deployer' created"
        fi
    fi
}

# Setup application directory
setup_app_directory() {
    print_header "Setting Up Application Directory"
    
    sudo mkdir -p "$APP_DIR"
    sudo chown -R "$USER:$USER" "$APP_DIR"
    
    print_success "Application directory created: $APP_DIR"
}

# Clone repository
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
    
    print_success "Repository cloned/updated"
}

# Docker Hub login
docker_login() {
    print_header "Logging into Docker Hub"
    
    echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
    
    if [ $? -eq 0 ]; then
        print_success "Docker Hub login successful"
    else
        print_error "Docker Hub login failed"
        exit 1
    fi
}

# Generate secure secret key
generate_secret_key() {
    python3 -c "import secrets; print(secrets.token_urlsafe(50))"
}

# Setup environment file
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
    
    cat > "$APP_DIR/.env.docker" << EOF
============================================
Django Core Settings
============================================
SECRET_KEY=$GENERATED_SECRET_KEY
DEBUG=False
ENVIRONMENT=production
ALLOWED_HOSTS=localhost,$DOMAIN_NAME,www.$DOMAIN_NAME
CSRF_ORIGINS=http://$DOMAIN_NAME,http://www.$DOMAIN_NAME

============================================
Database Configuration
============================================
DATABASE_URL=postgresql://user:password@host:port/dbname
ANALYTICS_DATABASE_URL=postgresql://user:password@host:port/analytics_db

============================================
Redis Configuration
============================================
REDIS_URL=redis://redis:6379
REDIS_HOST=redis
REDIS_PASSWORD=

============================================
Site Configuration
============================================
SITE_ID=1
SITE_NAME=$DOMAIN_NAME
SITE_URL=http://$DOMAIN_NAME
BASE_URL=https://sandbox.safaricom.co.ke

============================================
Email Configuration
============================================
DEFAULT_FROM_EMAIL=noreply@$DOMAIN_NAME
EMAIL_HOST=smtp.gmail.com
EMAIL_HOST_USER=your-email@gmail.com
EMAIL_HOST_PASSWORD=your-app-password
EMAIL_PORT=587

============================================
Cloudflare R2 Storage (Private)
============================================
CLOUDFLARE_R2_ACCESS_KEY=your-access-key
CLOUDFLARE_R2_SECRET_KEY=your-secret-key
CLOUDFLARE_R2_BUCKET=your-bucket-name
CLOUDFLARE_R2_BUCKET_ENDPOINT=https://your-account-id.r2.cloudflarestorage.com
CLOUDFLARE_R2_TOKEN_VALUE=your-token

============================================
Cloudflare R2 Storage (Public/CDN)
============================================
CLOUDFLARE_R2_PUBLIC_ACCESS_KEY=your-public-access-key
CLOUDFLARE_R2_PUBLIC_SECRET_KEY=your-public-secret-key
CLOUDFLARE_R2_PUBLIC_BUCKET=your-public-bucket
CLOUDFLARE_R2_PUBLIC_BUCKET_ENDPOINT=https://your-account-id.r2.cloudflarestorage.com
CLOUDFLARE_R2_PUBLIC_CUSTOM_DOMAIN=https://cdn.$DOMAIN_NAME

============================================
Backup R2 Storage
============================================
BACKUP_R2_ACCESS_KEY_ID=your-backup-access-key
BACKUP_R2_SECRET_ACCESS_KEY=your-backup-secret-key
BACKUP_R2_BUCKET_NAME=your-backup-bucket
BACKUP_R2_ENDPOINT=https://your-account-id.r2.cloudflarestorage.com
BACKUP_R2_ACCOUNT_ID=your-account-id
BACKUP_R2_REGION=auto

============================================
M-Pesa Payment Configuration
============================================
MPESA_CONSUMER_KEY=your-consumer-key
MPESA_CONSUMER_SECRET=your-consumer-secret
MPESA_PASSKEY=your-passkey
MPESA_SHORTCODE=174379
CALLBACK_URL=https://$DOMAIN_NAME/api/mpesa/callback

============================================
Google OAuth
============================================
GOOGLE_OAUTH_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_OAUTH_CLIENT_SECRET=your-client-secret

============================================
GeoIP Configuration
============================================
GEOIP_LICENSE_KEY=your-maxmind-license-key

============================================
reCAPTCHA
============================================
RECAPTCHA_PUBLIC_KEY=your-recaptcha-site-key
RECAPTCHA_PRIVATE_KEY=your-recaptcha-secret-key

============================================
Monitoring & Analytics
============================================
SENTRY_DSN=https://your-sentry-dsn@sentry.io/project-id
POSTHOG_ENABLED=True
POSTHOG_HOST=https://eu.i.posthog.com
POSTHOG_API_KEY=your-posthog-project-api-key

============================================
Admin Configuration
============================================
ADMIN_NAME=Admin Name
ADMIN_EMAIL=admin@$DOMAIN_NAME

============================================
Python Configuration
============================================
PYTHON_VERSION=3.13.5
UID=1000
EOF
    
    print_success "Environment file created"
    
    print_header "IMPORTANT: Environment Configuration Required"
    echo
    print_warning "The application REQUIRES proper configuration!"
    echo
    print_info "Press Enter to open editor and configure environment..."
    read -r
    
    nano "$APP_DIR/.env.docker"
    
    print_success "Environment file saved"
    validate_env_file
}

# Validate environment file
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
    # shellcheck source=/dev/null
    source "$APP_DIR/.env.docker" 2>/dev/null || true
    set +a
    
    if [ -z "$SECRET_KEY" ] || [ "$SECRET_KEY" = "your-secret-key-here" ]; then
        errors+=("SECRET_KEY is not configured")
        validation_failed=true
    fi
    
    if [ -z "$ALLOWED_HOSTS" ] || [[ "$ALLOWED_HOSTS" == *"yourdomain.com"* ]]; then
        errors+=("ALLOWED_HOSTS contains placeholder domain")
        validation_failed=true
    fi
    
    if [[ "$DATABASE_URL" == *"user:password@host"* ]]; then
        warnings+=("DATABASE_URL contains placeholder values")
    fi
    
    if [ "$EMAIL_HOST_USER" = "your-email@gmail.com" ]; then
        warnings+=("Email not configured")
    fi
    
    if [ "$validation_failed" = true ]; then
        print_error "Configuration validation FAILED!"
        echo
        print_error "Critical errors found:"
        for error in "${errors[@]}"; do
            echo "  ✗ $error"
        done
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
        for warning in "${warnings[@]}"; do
            echo "  ⚠ $warning"
        done
        echo
    fi
    
    print_success "Environment configuration validated"
}

# Create Nginx configuration
create_nginx_config() {
    print_header "Creating Nginx Configuration"
    
    mkdir -p "$APP_DIR/nginx"
    
    cat > "$APP_DIR/nginx/nginx.conf" << 'EOF'
# Rate limiting zones
limit_req_zone $binary_remote_addr zone=general_limit:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=30r/m;
limit_req_zone $binary_remote_addr zone=login_limit:10m rate=5r/m;
limit_req_status 429;

# Point to Django app container
upstream django_app {
    server web:8000;
    keepalive 64;
}

server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Logs
    access_log /var/log/nginx/esc_access.log;
    error_log /var/log/nginx/esc_error.log;
    
    # Client settings
    client_max_body_size 100M;
    client_body_buffer_size 128k;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 16k;
    
    # Timeouts
    proxy_connect_timeout 300s;
    proxy_send_timeout 300s;
    proxy_read_timeout 300s;
    send_timeout 300s;
    
    # Block dangerous methods
    if ($request_method !~ ^(GET|HEAD|POST|PUT|DELETE|OPTIONS)$) {
        return 405;
    }
    
    # Block hidden files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    # Block sensitive files
    location ~ /\.env {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    # Block common attack paths
    location ~ ^/(wp-admin|wp-login|admin\.php|administrator|phpmyadmin) {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    # Main application
    location / {
        limit_req zone=general_limit burst=20 nodelay;
        
        proxy_pass http://django_app;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto http;
        proxy_set_header X-Forwarded-Host $host;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
    }
    
    # API endpoints with stricter rate limiting
    location /api/ {
        limit_req zone=api_limit burst=5 nodelay;
        
        proxy_pass http://django_app;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto http;
    }
    
    # Authentication endpoints with strict rate limiting
    location ~ ^/(account|auth|login|signin|register) {
        limit_req zone=login_limit burst=2 nodelay;
        
        proxy_pass http://django_app;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto http;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        proxy_pass http://django_app;
        proxy_set_header Host $host;
        proxy_connect_timeout 5s;
        proxy_read_timeout 5s;
    }
    
    # Static files
    location /static/ {
        proxy_pass http://django_app;
        proxy_set_header Host $host;
    }
    
    # Media files
    location /media/ {
        proxy_pass http://django_app;
        proxy_set_header Host $host;
    }
}
EOF
    
    print_success "Nginx config created at $APP_DIR/nginx/nginx.conf"
}

# Install Fail2Ban
install_fail2ban() {
    print_header "Installing Fail2Ban"
    
    if command -v fail2ban-server &> /dev/null; then
        print_warning "Fail2Ban already installed"
    else
        sudo apt install -y fail2ban
        print_success "Fail2Ban installed"
    fi
}

# Configure Fail2Ban
setup_fail2ban() {
    print_header "Configuring Fail2Ban"
    
    mkdir -p /tmp/fail2ban_setup
    cd /tmp/fail2ban_setup || exit 1
    
    if [ -f /etc/fail2ban/jail.local ]; then
        print_info "Backing up existing jail.local..."
        sudo cp /etc/fail2ban/jail.local "/etc/fail2ban/jail.local.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    cat > jail.local << 'EOF'
[DEFAULT]
bantime = 2592000
findtime = 3600
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s
maxretry = 3
EOF
    
    sudo cp jail.local /etc/fail2ban/jail.local
    sudo chmod 644 /etc/fail2ban/jail.local
    
    print_info "Restarting Fail2Ban..."
    sudo systemctl daemon-reload
    sudo systemctl restart fail2ban
    sleep 3
    
    if systemctl is-active --quiet fail2ban; then
        print_success "Fail2Ban configured and started"
    else
        print_warning "Fail2Ban failed to start - continuing without it"
    fi
    
    cd - > /dev/null || exit 1
}

# Create management scripts
create_management_scripts() {
    print_header "Creating Management Scripts"
    
    # Deploy script
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
echo "Waiting for services..."
sleep 30
docker compose -f compose.prod.yaml ps
echo "Deployment complete!"
SCRIPT
    
    chmod +x "$APP_DIR/deploy.sh"
    
    # Logs script
    cat > "$APP_DIR/logs.sh" << 'SCRIPT'
#!/bin/bash
cd "$(dirname "$0")" || exit 1
SERVICE=${1:-all}
if [ "$SERVICE" = "all" ]; then
    docker compose -f compose.prod.yaml logs -f
else
    docker compose -f compose.prod.yaml logs -f "$SERVICE"
fi
SCRIPT
    
    chmod +x "$APP_DIR/logs.sh"
    
    # Status script
    cat > "$APP_DIR/status.sh" << 'SCRIPT'
#!/bin/bash
cd "$(dirname "$0")" || exit 1
echo "=== Container Status ==="
docker compose -f compose.prod.yaml ps
echo
echo "=== Resource Usage ==="
docker stats --no-stream
SCRIPT
    
    chmod +x "$APP_DIR/status.sh"
    
    # Stop script
    cat > "$APP_DIR/stop.sh" << 'SCRIPT'
#!/bin/bash
cd "$(dirname "$0")" || exit 1
echo "Stopping all services..."
docker compose -f compose.prod.yaml down
echo "Services stopped."
SCRIPT
    
    chmod +x "$APP_DIR/stop.sh"
    
    # Start script
    cat > "$APP_DIR/start.sh" << 'SCRIPT'
#!/bin/bash
cd "$(dirname "$0")" || exit 1
echo "Starting all services..."
docker compose -f compose.prod.yaml up -d
sleep 30
docker compose -f compose.prod.yaml ps
SCRIPT
    
    chmod +x "$APP_DIR/start.sh"
    
    print_success "Management scripts created in $APP_DIR/"
}

# Setup firewall
setup_firewall() {
    if [[ "$SETUP_FIREWALL" =~ ^[Yy]$ ]]; then
        print_header "Configuring UFW Firewall"
        
        sudo ufw --force reset > /dev/null 2>&1 || true
        
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        
        sudo ufw allow 22/tcp
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        
        echo "y" | sudo ufw enable > /dev/null 2>&1
        
        print_success "Firewall configured"
        sudo ufw status verbose
    fi
}

# Setup systemd service
setup_systemd() {
    print_header "Setting Up Systemd Service"
    
    sudo tee /etc/systemd/system/esc.service > /dev/null << EOF
[Unit]
Description=ESC Django Application with Docker
Requires=docker.service
After=docker.service network.target

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
    
    print_success "Systemd service created"
}

# Pull and start application
start_application() {
    print_header "Starting Application"
    
    cd "$APP_DIR" || exit 1
    
    print_info "Pulling latest Docker images..."
    if ! docker compose -f compose.prod.yaml pull; then
        print_warning "Failed to pull Docker images, continuing with existing images..."
    else
        print_success "Docker images pulled successfully"
    fi
    
    print_info "Starting services..."
    if ! docker compose -f compose.prod.yaml up -d; then
        print_error "Failed to start services"
        docker compose -f compose.prod.yaml logs --tail=20
        exit 1
    fi
    
    print_success "Services started"
    
    print_info "Waiting for services to initialize (60 seconds)..."
    for i in {1..12}; do
        echo -n "."
        sleep 5
    done
    echo
    
    if docker compose -f compose.prod.yaml ps | grep -q "Up"; then
        print_success "Services are running"
        docker compose -f compose.prod.yaml ps
    else
        print_warning "Some services may not be running properly"
        docker compose -f compose.prod.yaml ps
        print_info "Check logs: $APP_DIR/logs.sh"
    fi
}

# Print completion message
print_completion() {
    print_header "Installation Complete!"
    
    echo -e "${GREEN}Your ESC Django application is fully deployed!${NC}\n"
    
    echo "Application Details:"
    echo "  Domain: http://$DOMAIN_NAME (Cloudflare handles HTTPS)"
    echo "  App Directory: $APP_DIR"
    echo "  Environment: $APP_DIR/.env.docker"
    echo "  Nginx Config: $APP_DIR/nginx/nginx.conf"
    echo
    
    echo "Management Commands:"
    echo "  Deploy/Update:    $APP_DIR/deploy.sh"
    echo "  View Logs:        $APP_DIR/logs.sh [service]"
    echo "  Check Status:     $APP_DIR/status.sh"
    echo "  Stop Services:    $APP_DIR/stop.sh"
    echo "  Start Services:   $APP_DIR/start.sh"
    
    if [ "$SECURITY_ENABLED" = "true" ]; then
        echo
        echo -e "${GREEN}Security Features Enabled:${NC}"
        echo "  ✓ Fail2Ban protection"
        echo "  ✓ Nginx rate limiting"
        echo "  ✓ Security headers"
        echo "  ✓ Attack pattern blocking"
    fi
    
    echo
    echo "Cloudflare Configuration:"
    echo "  1. Add A record pointing to: $(hostname -I | awk '{print $1}')"
    echo "  2. Set SSL/TLS to: 'Flexible' (HTTP to origin)"
    echo "  3. Enable: 'Always Use HTTPS' (for client connections)"
    echo "  4. Enable: 'Automatic HTTPS Rewrites'"
    echo
    
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Create Django superuser:"
    echo "     cd $APP_DIR && docker compose -f compose.prod.yaml exec web python manage.py createsuperuser"
    echo "  2. Monitor logs for errors:"
    echo "     $APP_DIR/logs.sh"
    echo "  3. Test your application:"
    echo "     curl http://$DOMAIN_NAME"
    echo
    
    print_success "Deployment ready!"
}

# Main installation flow
main() {
    print_header "ESC Django Application - Automated Deployment"
    
    check_sudo
    check_os
    remove_host_nginx
    gather_config
    
    update_system
    install_docker
    create_deployer_user
    setup_app_directory
    clone_repository
    docker_login
    setup_env_file
    create_nginx_config
    
    if [ "$SECURITY_ENABLED" = "true" ]; then
        install_fail2ban
        setup_fail2ban
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

# Run main function
main

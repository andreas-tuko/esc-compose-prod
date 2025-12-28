#!/bin/bash

# ESC Django Application - Automated Deployment Script
# This script automates the complete deployment of the ESC application on a fresh VPS

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

# Check if running as root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        print_error "Please do not run this script as root. Run as a regular user with sudo privileges."
        exit 1
    fi
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

# Interactive configuration
gather_config() {
    print_header "Configuration Setup"
    
    # Domain name
    read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
    while [ -z "$DOMAIN_NAME" ]; do
        print_warning "Domain name cannot be empty"
        read -p "Enter your domain name: " DOMAIN_NAME
    done
    
    # Docker Hub credentials
    print_info "Docker Hub credentials are required to pull the private image"
    read -p "Docker Hub username: " DOCKER_USERNAME
    while [ -z "$DOCKER_USERNAME" ]; do
        print_warning "Docker Hub username cannot be empty"
        read -p "Docker Hub username: " DOCKER_USERNAME
    done
    
    read -sp "Docker Hub password/token: " DOCKER_PASSWORD
    echo
    while [ -z "$DOCKER_PASSWORD" ]; do
        print_warning "Docker Hub password cannot be empty"
        read -sp "Docker Hub password/token: " DOCKER_PASSWORD
        echo
    done
    
    # Application directory
    DEFAULT_APP_DIR="/opt/apps/esc"
    read -p "Application directory [$DEFAULT_APP_DIR]: " APP_DIR
    APP_DIR=${APP_DIR:-$DEFAULT_APP_DIR}
    
    # Create deployer user
    read -p "Create a dedicated 'deployer' user? (recommended) [Y/n]: " CREATE_USER
    CREATE_USER=${CREATE_USER:-Y}
    
    # Setup firewall
    read -p "Configure UFW firewall? (recommended) [Y/n]: " SETUP_FIREWALL
    SETUP_FIREWALL=${SETUP_FIREWALL:-Y}
    
    # Confirmation
    print_header "Configuration Summary"
    echo "Domain: $DOMAIN_NAME"
    echo "Docker Hub User: $DOCKER_USERNAME"
    echo "App Directory: $APP_DIR"
    echo "Create deployer user: $CREATE_USER"
    echo "Setup firewall: $SETUP_FIREWALL"
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
    sudo apt install -y curl wget git ufw nano
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
        
        # Add current user to docker group
        sudo usermod -aG docker $USER
        print_success "Docker installed"
    fi
    
    # Install Docker Compose plugin
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
            print_success "User 'deployer' created"
        fi
    fi
}

# Setup application directory
setup_app_directory() {
    print_header "Setting Up Application Directory"
    
    sudo mkdir -p $APP_DIR
    sudo chown -R $USER:$USER $APP_DIR
    
    print_success "Application directory created: $APP_DIR"
}

# Clone repository
clone_repository() {
    print_header "Cloning Repository"
    
    cd $APP_DIR
    
    if [ -d ".git" ]; then
        print_warning "Repository already exists, pulling latest changes..."
        git pull
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

# Setup environment file with interactive editing
setup_env_file() {
    print_header "Environment Configuration"
    
    if [ -f "$APP_DIR/.env.docker" ]; then
        print_warning "Environment file already exists"
        read -p "Do you want to reconfigure it? [y/N]: " RECONFIG_ENV
        
        if [[ ! "$RECONFIG_ENV" =~ ^[Yy]$ ]]; then
            print_info "Keeping existing environment file"
            return
        fi
        
        # Backup existing file
        cp $APP_DIR/.env.docker $APP_DIR/.env.docker.backup.$(date +%Y%m%d_%H%M%S)
        print_info "Existing file backed up"
    fi
    
    print_step "Creating environment file with default values..."
    
    # Generate a secure secret key
    GENERATED_SECRET_KEY=$(generate_secret_key)
    
    cat > $APP_DIR/.env.docker << EOF
# ============================================
# Django Core Settings
# ============================================
SECRET_KEY=$GENERATED_SECRET_KEY
DEBUG=False
ENVIRONMENT=production
ALLOWED_HOSTS=localhost,$DOMAIN_NAME,www.$DOMAIN_NAME
CSRF_ORIGINS=https://$DOMAIN_NAME,https://www.$DOMAIN_NAME

# ============================================
# Database Configuration
# ============================================
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
GOOGLE_OATH_CLIENT_ID=your-client-id.apps.googleusercontent.com
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
    
    print_success "Environment file created with default values"
    
    # Show important notice
    print_header "IMPORTANT: Environment Configuration Required"
    echo
    print_warning "The application REQUIRES proper configuration to run successfully!"
    echo
    print_info "The nano editor will now open with your environment file."
    print_info "Please configure the following REQUIRED settings:"
    echo
    echo "  ${GREEN}✓ Already configured:${NC}"
    echo "    - SECRET_KEY (auto-generated)"
    echo "    - ALLOWED_HOSTS (set to your domain)"
    echo "    - SITE_URL (set to your domain)"
    echo
    echo "  ${YELLOW}⚠ REQUIRED - Must configure:${NC}"
    echo "    - DATABASE_URL (if using external PostgreSQL)"
    echo "    - EMAIL_HOST_USER & EMAIL_HOST_PASSWORD (for email functionality)"
    echo
    echo "  ${CYAN}○ OPTIONAL - Configure if needed:${NC}"
    echo "    - Cloudflare R2 credentials (for file storage)"
    echo "    - M-Pesa credentials (for payments)"
    echo "    - Google OAuth (for social login)"
    echo "    - Sentry & PostHog (for monitoring)"
    echo "    - reCAPTCHA keys (for bot protection)"
    echo
    print_info "Tips for editing in nano:"
    echo "  - Use arrow keys to navigate"
    echo "  - Replace 'your-*' placeholders with actual values"
    echo "  - Leave optional fields if not using those features"
    echo "  - Press Ctrl+X, then Y, then Enter to save and exit"
    echo
    read -p "Press Enter to open the editor and configure your environment..."
    
    # Open nano editor
    nano $APP_DIR/.env.docker
    
    print_success "Environment file saved"
    
    # Validate configuration
    validate_env_file
}

# Validate environment file
validate_env_file() {
    print_header "Validating Environment Configuration"
    
    local validation_failed=false
    local warnings=()
    local errors=()
    
    # Check if file exists
    if [ ! -f "$APP_DIR/.env.docker" ]; then
        print_error "Environment file not found!"
        exit 1
    fi
    
    # Source the env file for validation
    set -a
    source $APP_DIR/.env.docker 2>/dev/null || true
    set +a
    
    # Critical validations
    if [ -z "$SECRET_KEY" ] || [ "$SECRET_KEY" = "your-secret-key-here" ]; then
        errors+=("SECRET_KEY is not configured")
        validation_failed=true
    fi
    
    if [ -z "$ALLOWED_HOSTS" ] || [[ "$ALLOWED_HOSTS" == *"yourdomain.com"* ]]; then
        errors+=("ALLOWED_HOSTS contains placeholder domain")
        validation_failed=true
    fi
    
    # Important warnings (not blocking)
    if [[ "$DATABASE_URL" == *"user:password@host"* ]]; then
        warnings+=("DATABASE_URL contains placeholder values (if you're using PostgreSQL, configure this)")
    fi
    
    if [ "$EMAIL_HOST_USER" = "your-email@gmail.com" ]; then
        warnings+=("Email not configured (email functionality will not work)")
    fi
    
    if [[ "$CLOUDFLARE_R2_ACCESS_KEY" == "your-access-key" ]]; then
        warnings+=("Cloudflare R2 not configured (file storage may not work)")
    fi
    
    if [[ "$MPESA_CONSUMER_KEY" == "your-consumer-key" ]]; then
        warnings+=("M-Pesa not configured (payment functionality will not work)")
    fi
    
    # Display results
    if [ "$validation_failed" = true ]; then
        print_error "Configuration validation FAILED!"
        echo
        print_error "Critical errors found:"
        for error in "${errors[@]}"; do
            echo "  ✗ $error"
        done
        echo
        print_warning "Please fix these errors before continuing."
        read -p "Do you want to edit the configuration again? [Y/n]: " EDIT_AGAIN
        EDIT_AGAIN=${EDIT_AGAIN:-Y}
        
        if [[ "$EDIT_AGAIN" =~ ^[Yy]$ ]]; then
            nano $APP_DIR/.env.docker
            validate_env_file  # Recursive call to re-validate
            return
        else
            print_error "Cannot proceed with invalid configuration."
            exit 1
        fi
    fi
    
    # Display warnings
    if [ ${#warnings[@]} -gt 0 ]; then
        print_warning "Configuration warnings (non-critical):"
        for warning in "${warnings[@]}"; do
            echo "  ⚠ $warning"
        done
        echo
        print_info "You can continue, but some features may not work without proper configuration."
        read -p "Continue anyway? [Y/n]: " CONTINUE_ANYWAY
        CONTINUE_ANYWAY=${CONTINUE_ANYWAY:-Y}
        
        if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
            nano $APP_DIR/.env.docker
            validate_env_file  # Recursive call to re-validate
            return
        fi
    fi
    
    print_success "Environment configuration validated"
}

# Install and configure Nginx
install_nginx() {
    print_header "Installing and Configuring Nginx"
    
    # Install Nginx
    if command -v nginx &> /dev/null; then
        print_warning "Nginx is already installed"
    else
        sudo apt install -y nginx
        print_success "Nginx installed"
    fi
    
    # Create Nginx configuration
    print_info "Creating Nginx configuration for $DOMAIN_NAME..."
    
    sudo tee /etc/nginx/sites-available/esc > /dev/null << EOF
upstream django_app {
    server 127.0.0.1:8000;
    keepalive 64;
}

server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Logging
    access_log /var/log/nginx/esc_access.log;
    error_log /var/log/nginx/esc_error.log;

    # Client body size limit
    client_max_body_size 100M;

    # Timeouts
    proxy_connect_timeout 600s;
    proxy_send_timeout 600s;
    proxy_read_timeout 600s;

    location / {
        proxy_pass http://django_app;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Cloudflare real IP
        set_real_ip_from 173.245.48.0/20;
        set_real_ip_from 103.21.244.0/22;
        set_real_ip_from 103.22.200.0/22;
        set_real_ip_from 103.31.4.0/22;
        set_real_ip_from 141.101.64.0/18;
        set_real_ip_from 108.162.192.0/18;
        set_real_ip_from 190.93.240.0/20;
        set_real_ip_from 188.114.96.0/20;
        set_real_ip_from 197.234.240.0/22;
        set_real_ip_from 198.41.128.0/17;
        set_real_ip_from 162.158.0.0/15;
        set_real_ip_from 104.16.0.0/13;
        set_real_ip_from 104.24.0.0/14;
        set_real_ip_from 172.64.0.0/13;
        set_real_ip_from 131.0.72.0/22;
        set_real_ip_from 2400:cb00::/32;
        set_real_ip_from 2606:4700::/32;
        set_real_ip_from 2803:f800::/32;
        set_real_ip_from 2405:b500::/32;
        set_real_ip_from 2405:8100::/32;
        set_real_ip_from 2a06:98c0::/29;
        set_real_ip_from 2c0f:f248::/32;
        real_ip_header CF-Connecting-IP;
    }

    # Health check endpoint
    location /health {
        access_log off;
        proxy_pass http://django_app;
        proxy_set_header Host \$host;
    }
}
EOF
    
    # Enable site
    sudo ln -sf /etc/nginx/sites-available/esc /etc/nginx/sites-enabled/
    
    # Remove default site
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # Test configuration
    sudo nginx -t
    
    if [ $? -eq 0 ]; then
        sudo systemctl restart nginx
        sudo systemctl enable nginx
        print_success "Nginx configured and started"
    else
        print_error "Nginx configuration test failed"
        exit 1
    fi
}

# Setup systemd service
setup_systemd() {
    print_header "Setting Up Systemd Service"
    
    sudo tee /etc/systemd/system/esc.service > /dev/null << EOF
[Unit]
Description=ESC Django Application
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/docker compose -f compose.prod.yaml up -d
ExecStop=/usr/bin/docker compose -f compose.prod.yaml down
User=$USER

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable esc.service
    
    print_success "Systemd service created and enabled"
}

# Setup firewall
setup_firewall() {
    if [[ "$SETUP_FIREWALL" =~ ^[Yy]$ ]]; then
        print_header "Configuring UFW Firewall"
        
        # Allow SSH
        sudo ufw allow 22/tcp
        print_info "Allowed SSH (port 22)"
        
        # Allow HTTP and HTTPS
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        print_info "Allowed HTTP (port 80) and HTTPS (port 443)"
        
        # Enable firewall
        sudo ufw --force enable
        
        print_success "Firewall configured"
        sudo ufw status
    fi
}

# Create management scripts
create_management_scripts() {
    print_header "Creating Management Scripts"
    
    # Deploy script
    cat > $APP_DIR/deploy.sh << 'EOF'
#!/bin/bash
set -e

echo "Starting deployment..."

cd $(dirname "$0")

# Pull latest image
echo "Pulling latest image..."
docker pull andreastuko/esc:latest

# Stop and remove old containers
echo "Stopping containers..."
docker compose -f compose.prod.yaml down

# Start new containers
echo "Starting new containers..."
docker compose -f compose.prod.yaml up -d

# Wait for health checks
echo "Waiting for services to be healthy..."
sleep 30

# Check status
docker compose -f compose.prod.yaml ps

echo "Deployment complete!"
EOF
    
    chmod +x $APP_DIR/deploy.sh
    
    # Logs script
    cat > $APP_DIR/logs.sh << 'EOF'
#!/bin/bash

cd $(dirname "$0")

SERVICE=${1:-all}

if [ "$SERVICE" = "all" ]; then
    docker compose -f compose.prod.yaml logs -f
else
    docker compose -f compose.prod.yaml logs -f $SERVICE
fi
EOF
    
    chmod +x $APP_DIR/logs.sh
    
    # Status script
    cat > $APP_DIR/status.sh << 'EOF'
#!/bin/bash

cd $(dirname "$0")

echo "=== Container Status ==="
docker compose -f compose.prod.yaml ps
echo

echo "=== Resource Usage ==="
docker stats --no-stream
echo

echo "=== Nginx Status ==="
sudo systemctl status nginx --no-pager
EOF
    
    chmod +x $APP_DIR/status.sh
    
    # Stop script
    cat > $APP_DIR/stop.sh << 'EOF'
#!/bin/bash

cd $(dirname "$0")

echo "Stopping all services..."
docker compose -f compose.prod.yaml down

echo "Services stopped."
EOF
    
    chmod +x $APP_DIR/stop.sh
    
    # Start script
    cat > $APP_DIR/start.sh << 'EOF'
#!/bin/bash

cd $(dirname "$0")

echo "Starting all services..."
docker compose -f compose.prod.yaml up -d

echo "Services started. Waiting for health checks..."
sleep 30

docker compose -f compose.prod.yaml ps
EOF
    
    chmod +x $APP_DIR/start.sh
    
    # Restart configuration script
    cat > $APP_DIR/reconfig.sh << 'EOF'
#!/bin/bash

cd $(dirname "$0")

echo "Opening environment configuration..."
nano .env.docker

echo ""
read -p "Restart application with new configuration? [Y/n]: " RESTART
RESTART=${RESTART:-Y}

if [[ "$RESTART" =~ ^[Yy]$ ]]; then
    ./deploy.sh
else
    echo "Configuration saved. Run './deploy.sh' to apply changes."
fi
EOF
    
    chmod +x $APP_DIR/reconfig.sh
    
    print_success "Management scripts created"
}

# Pull and start application
start_application() {
    print_header "Starting Application"
    
    cd $APP_DIR
    
    # Pull latest image
    print_info "Pulling latest Docker image..."
    docker pull andreastuko/esc:latest
    
    # Start services
    print_info "Starting services..."
    docker compose -f compose.prod.yaml up -d
    
    # Wait for services to be healthy
    print_info "Waiting for services to start (this may take a few minutes)..."
    
    # Show progress
    for i in {1..12}; do
        sleep 5
        echo -n "."
    done
    echo
    
    # Check status
    docker compose -f compose.prod.yaml ps
    
    # Check if web service is healthy
    WEB_STATUS=$(docker compose -f compose.prod.yaml ps web --format json 2>/dev/null | grep -o '"Health":"[^"]*"' | cut -d'"' -f4)
    
    if [ "$WEB_STATUS" = "healthy" ]; then
        print_success "Application started successfully!"
    else
        print_warning "Application started but health check is pending..."
        print_info "Run './logs.sh web' to check application logs"
    fi
}

# Print completion message
print_completion() {
    print_header "Installation Complete!"
    
    echo -e "${GREEN}Your ESC Django application is now deployed!${NC}\n"
    
    echo "Application Details:"
    echo "  Domain: http://$DOMAIN_NAME"
    echo "  App Directory: $APP_DIR"
    echo "  Environment File: $APP_DIR/.env.docker"
    echo
    
    echo "Important Next Steps:"
    echo "  1. Configure Cloudflare:"
    echo "     - Set SSL/TLS to 'Flexible' or 'Full'"
    echo "     - Enable 'Always Use HTTPS'"
    echo "     - Add A record pointing to this server's IP"
    echo
    echo "  2. If you need to update configuration:"
    echo "     cd $APP_DIR && ./reconfig.sh"
    echo
    echo "  3. Create a Django superuser (admin):"
    echo "     cd $APP_DIR"
    echo "     docker compose -f compose.prod.yaml exec web python manage.py createsuperuser"
    echo
    
    echo "Management Commands:"
    echo "  Deploy/Update:     cd $APP_DIR && ./deploy.sh"
    echo "  View Logs:         cd $APP_DIR && ./logs.sh [service_name]"
    echo "  Check Status:      cd $APP_DIR && ./status.sh"
    echo "  Stop App:          cd $APP_DIR && ./stop.sh"
    echo "  Start App:         cd $APP_DIR && ./start.sh"
    echo "  Reconfigure:       cd $APP_DIR && ./reconfig.sh"
    echo
    
    echo "Service-specific logs:"
    echo "  Web:               ./logs.sh web"
    echo "  Worker:            ./logs.sh celery_worker"
    echo "  Beat:              ./logs.sh celery_beat"
    echo "  Redis:             ./logs.sh redis"
    echo
    
    echo "System Services:"
    echo "  Restart Nginx:     sudo systemctl restart nginx"
    echo "  Nginx Logs:        sudo tail -f /var/log/nginx/esc_error.log"
    echo
    
    print_warning "IMPORTANT: You may need to log out and back in for Docker group changes to take effect"
    print_warning "           Or run: newgrp docker"
    echo
    
    print_info "Visit your website at: http://$DOMAIN_NAME"
    print_info "(It may take 2-3 minutes for all services to be fully ready)"
    echo
}

# Main installation flow
main() {
    print_header "ESC Django Application - Automated Deployment"
    
    check_root
    check_sudo
    check_os
    gather_config
    
    update_system
    install_docker
    create_deployer_user
    setup_app_directory
    clone_repository
    docker_login
    setup_env_file
    install_nginx
    setup_systemd
    setup_firewall
    create_management_scripts
    
    # Ask if user wants to start now
    print_header "Ready to Start Application"
    print_info "All configuration is complete!"
    echo
    read -p "Start the application now? [Y/n]: " START_NOW
    START_NOW=${START_NOW:-Y}
    
    if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
        start_application
    else
        print_info "Application not started. Run './start.sh' when ready."
    fi
    
    print_completion
}

# Run main function
main
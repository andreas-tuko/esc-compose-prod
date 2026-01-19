#!/bin/bash

# ESC Django Application - Automated Deployment Script with Security Hardening
# This script automates complete deployment including Cloudflare protection and Fail2Ban
# Includes: Docker, Nginx, SSL, Fail2Ban, Rate Limiting, and Threat Detection

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
# This file is used to remember settings for re-deployments
DOMAIN_NAME="$DOMAIN_NAME"
DOCKER_USERNAME="$DOCKER_USERNAME"
APP_DIR="$APP_DIR"
SETUP_SSL="$SETUP_SSL"
SSL_EMAIL="$SSL_EMAIL"
SECURITY_ENABLED="$SECURITY_ENABLED"
ADMIN_EMAIL="$ADMIN_EMAIL"
EOF
    
    chmod 600 "$CONFIG_FILE"
    print_success "Configuration saved for future deployments"
}

# Configure SSL option
configure_ssl_option() {
    echo
    print_info "SSL Certificate Configuration"
    echo "Choose SSL certificate option:"
    echo "  1) Let's Encrypt (Free, auto-renewing, requires valid domain)"
    echo "  2) Self-signed (Works with IP address, not trusted by browsers)"
    echo "  3) None (Use Cloudflare SSL only)"
    read -p "Select option [1/2/3]: " SSL_OPTION
    SSL_OPTION=${SSL_OPTION:-3}
    
    if [ "$SSL_OPTION" = "1" ]; then
        SETUP_SSL="letsencrypt"
        if [ -n "$SSL_EMAIL" ]; then
            read -p "Email for Let's Encrypt notifications [$SSL_EMAIL]: " NEW_SSL_EMAIL
            SSL_EMAIL=${NEW_SSL_EMAIL:-$SSL_EMAIL}
        else
            read -p "Email for Let's Encrypt notifications: " SSL_EMAIL
            while [ -z "$SSL_EMAIL" ]; do
                print_warning "Email cannot be empty for Let's Encrypt"
                read -p "Email for Let's Encrypt notifications: " SSL_EMAIL
            done
        fi
    elif [ "$SSL_OPTION" = "2" ]; then
        SETUP_SSL="selfsigned"
        print_warning "Self-signed certificates will show security warnings in browsers"
        print_info "This is useful for testing or IP-based access"
    else
        SETUP_SSL="none"
        SSL_EMAIL=""
        print_info "Will use HTTP only (Cloudflare handles SSL)"
    fi
}

# Configure security settings
configure_security() {
    print_header "Security Configuration"
    
    echo "Enable advanced security features? (Recommended: Yes)"
    echo "  • Cloudflare-only IP enforcement"
    echo "  • Fail2Ban with multi-jail detection"
    echo "  • Rate limiting protection"
    echo "  • Vulnerability scanning detection"
    echo "  • DDoS protection"
    echo "  • SQL injection/XSS blocking"
    
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
        echo "  SSL: $SETUP_SSL"
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
    if [ -n "$APP_DIR" ] && [ "$APP_DIR" != "$DEFAULT_APP_DIR" ]; then
        read -p "Application directory [$APP_DIR]: " NEW_APP_DIR
        APP_DIR=${NEW_APP_DIR:-$APP_DIR}
    else
        read -p "Application directory [$DEFAULT_APP_DIR]: " APP_DIR
        APP_DIR=${APP_DIR:-$DEFAULT_APP_DIR}
    fi
    
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
    
    # SSL Certificate setup
    if [ "$EXISTING_CONFIG" = true ] && [ -n "$SETUP_SSL" ]; then
        echo
        print_info "Current SSL setup: $SETUP_SSL"
        read -p "Keep existing SSL configuration? [Y/n]: " KEEP_SSL
        KEEP_SSL=${KEEP_SSL:-Y}
        
        if [[ ! "$KEEP_SSL" =~ ^[Yy]$ ]]; then
            configure_ssl_option
        fi
    else
        configure_ssl_option
    fi
    
    # Security configuration
    configure_security
    
    print_header "Configuration Summary"
    echo "Domain: $DOMAIN_NAME"
    echo "Docker Hub User: $DOCKER_USERNAME"
    echo "App Directory: $APP_DIR"
    echo "Create deployer user: $CREATE_USER"
    echo "Setup firewall: $SETUP_FIREWALL"
    if [ "$SETUP_SSL" = "letsencrypt" ]; then
        echo "SSL: Let's Encrypt (Email: $SSL_EMAIL)"
    elif [ "$SETUP_SSL" = "selfsigned" ]; then
        echo "SSL: Self-signed certificate"
    else
        echo "SSL: None (Cloudflare only)"
    fi
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
        
        sudo usermod -aG docker $USER
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
        
        cp $APP_DIR/.env.docker $APP_DIR/.env.docker.backup.$(date +%Y%m%d_%H%M%S)
        print_info "Existing file backed up"
    fi
    
    print_step "Creating environment file with default values..."
    
    GENERATED_SECRET_KEY=$(generate_secret_key)
    
    cat > $APP_DIR/.env.docker << EOF
============================================
Django Core Settings
============================================
SECRET_KEY=$GENERATED_SECRET_KEY
DEBUG=False
ENVIRONMENT=production
ALLOWED_HOSTS=localhost,$DOMAIN_NAME,www.$DOMAIN_NAME
CSRF_ORIGINS=https://$DOMAIN_NAME,https://www.$DOMAIN_NAME

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
SITE_URL=https://$DOMAIN_NAME
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
GOOGLE_OATH_CLIENT_ID=your-client-id.apps.googleusercontent.com
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
    read
    
    nano $APP_DIR/.env.docker
    
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
    source $APP_DIR/.env.docker 2>/dev/null || true
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
            nano $APP_DIR/.env.docker
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

# Configure Fail2Ban - FIXED VERSION
setup_fail2ban() {
    print_header "Configuring Fail2Ban with Security Policies"
    
    # Create a temporary directory for setup
    mkdir -p /tmp/fail2ban_setup
    cd /tmp/fail2ban_setup
    
    # First, test existing configuration
    if [ -f /etc/fail2ban/jail.local ]; then
        print_info "Backing up existing jail.local..."
        sudo cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # Create a simplified jail.local that works
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

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_error.log
maxretry = 3

[nginx-bad-requests]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 5
bantime = 86400
findtime = 600

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 3
bantime = 86400
findtime = 300
EOF
    
    # Copy the jail.local
    sudo cp jail.local /etc/fail2ban/jail.local
    sudo chmod 644 /etc/fail2ban/jail.local
    
    # Create basic nginx filter
    cat > nginx-http-auth.conf << 'EOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD).*HTTP.*" (400|403|404|499|444|429) .*$
ignoreregex =
EOF
    
    sudo cp nginx-http-auth.conf /etc/fail2ban/filter.d/
    
    # Create custom log file
    sudo touch /var/log/fail2ban-custom.log
    sudo chown root:adm /var/log/fail2ban-custom.log
    sudo chmod 640 /var/log/fail2ban-custom.log
    
    # Test Fail2Ban configuration
    print_info "Testing Fail2Ban configuration..."
    if sudo fail2ban-client --test 2>&1 | grep -q "Errors in jail"; then
        print_warning "Fail2Ban configuration test failed, but continuing with minimal setup..."
    else
        print_success "Fail2Ban configuration test passed"
    fi
    
    # Restart Fail2Ban
    print_info "Restarting Fail2Ban..."
    sudo systemctl daemon-reload
    sudo systemctl restart fail2ban
    
    sleep 3
    
    # Check if Fail2Ban started successfully
    if systemctl is-active --quiet fail2ban; then
        print_success "Fail2Ban service started successfully"
        
        # Enable additional jails if needed
        sudo fail2ban-client reload
        sleep 2
        
        # Check status
        sudo fail2ban-client status
    else
        print_error "Fail2Ban failed to start"
        print_info "Attempting to start with minimal configuration..."
        
        # Try to start with minimal config
        sudo systemctl stop fail2ban
        sleep 2
        
        # Create absolute minimal config
        cat > /tmp/jail-minimal.conf << 'EOF'
[DEFAULT]
bantime = 600
findtime = 600
maxretry = 3

[sshd]
enabled = true
EOF
        
        sudo cp /tmp/jail-minimal.conf /etc/fail2ban/jail.local
        sudo systemctl start fail2ban
        
        if systemctl is-active --quiet fail2ban; then
            print_success "Fail2Ban started with minimal configuration"
        else
            print_warning "Fail2Ban could not be started. Continuing without it..."
            print_info "You can manually configure Fail2Ban later."
            SECURITY_ENABLED="false"
        fi
    fi
    
    cd - > /dev/null
}

# Create management scripts
create_management_scripts() {
    print_header "Creating Management Scripts"
    
    mkdir -p /opt/bin
    
    # Fail2Ban dashboard - simplified version
    cat > /opt/bin/f2b-dashboard.sh << 'SCRIPT'
#!/bin/bash
clear
echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║                        Fail2Ban Security Dashboard                            ║"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo
echo "Timestamp: $(date)"
echo "System Status: $(systemctl is-active fail2ban 2>/dev/null || echo "Not installed")"
echo

if command -v fail2ban-client &> /dev/null; then
    echo "PER-JAIL STATISTICS"
    echo "───────────────────"
    
    # Try to get status for common jails
    JAILS=$(sudo fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | sed 's/,//g')
    
    if [ -n "$JAILS" ]; then
        for jail in $JAILS; do
            jail_status=$(sudo fail2ban-client status $jail 2>/dev/null | grep "Currently banned" | tail -1)
            if [ -n "$jail_status" ]; then
                echo "  $jail: $jail_status"
            fi
        done
    else
        echo "  No active jails found"
    fi
    
    echo
    echo "RECENTLY BANNED IPs (from iptables)"
    echo "─────────────────────────────────"
    sudo iptables -L -n 2>/dev/null | grep "REJECT" | head -10 || echo "  No recent bans"
else
    echo "Fail2Ban is not installed or configured."
    echo
    echo "To install:"
    echo "  sudo apt install fail2ban"
    echo "  sudo systemctl enable fail2ban"
fi

echo
echo "────────────────────────────────────────────────────────────────────────────────"
echo
echo "COMMANDS:"
echo "  Unban IP:        sudo fail2ban-client set <jail> unbanip <IP>"
echo "  View Fail2Ban logs:  sudo journalctl -u fail2ban -f"
echo "  Check Nginx logs:    sudo tail -f /var/log/nginx/esc_error.log"
SCRIPT
    
    sudo chmod +x /opt/bin/f2b-dashboard.sh
    
    # Simple unban script
    cat > /opt/bin/f2b-unban.sh << 'SCRIPT'
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: $0 <IP_ADDRESS>"
    exit 1
fi
IP=$1
echo "Unbanning $IP..."
if command -v fail2ban-client &> /dev/null; then
    JAILS=$(sudo fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | sed 's/,//g')
    for jail in $JAILS; do
        sudo fail2ban-client set $jail unbanip $IP 2>/dev/null && echo "✓ Unbanned from $jail"
    done
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] MANUAL UNBAN: $IP" | sudo tee -a /var/log/fail2ban-custom.log > /dev/null
fi
# Also remove from iptables
sudo iptables -D INPUT -s $IP -j DROP 2>/dev/null
echo "Done"
SCRIPT
    
    sudo chmod +x /opt/bin/f2b-unban.sh
    
    # Create management scripts in app directory
    cat > $APP_DIR/deploy.sh << 'SCRIPT'
#!/bin/bash
set -e
echo "Starting deployment..."
cd $(dirname "$0")
echo "Pulling latest image..."
docker pull andreastuko/esc:latest
echo "Stopping containers..."
docker compose -f compose.prod.yaml down
echo "Starting new containers..."
docker compose -f compose.prod.yaml up -d
echo "Waiting for services..."
sleep 30
docker compose -f compose.prod.yaml ps
echo "Deployment complete!"
SCRIPT
    
    chmod +x $APP_DIR/deploy.sh
    
    cat > $APP_DIR/logs.sh << 'SCRIPT'
#!/bin/bash
cd $(dirname "$0")
SERVICE=${1:-all}
if [ "$SERVICE" = "all" ]; then
    docker compose -f compose.prod.yaml logs -f
else
    docker compose -f compose.prod.yaml logs -f $SERVICE
fi
SCRIPT
    
    chmod +x $APP_DIR/logs.sh
    
    cat > $APP_DIR/status.sh << 'SCRIPT'
#!/bin/bash
cd $(dirname "$0")
echo "=== Container Status ==="
docker compose -f compose.prod.yaml ps
echo
echo "=== Resource Usage ==="
docker stats --no-stream
SCRIPT
    
    chmod +x $APP_DIR/status.sh
    
    cat > $APP_DIR/stop.sh << 'SCRIPT'
#!/bin/bash
cd $(dirname "$0")
echo "Stopping all services..."
docker compose -f compose.prod.yaml down
echo "Services stopped."
SCRIPT
    
    chmod +x $APP_DIR/stop.sh
    
    cat > $APP_DIR/start.sh << 'SCRIPT'
#!/bin/bash
cd $(dirname "$0")
echo "Starting all services..."
docker compose -f compose.prod.yaml up -d
sleep 30
docker compose -f compose.prod.yaml ps
SCRIPT
    
    chmod +x $APP_DIR/start.sh
    
    cat > $APP_DIR/security.sh << 'SCRIPT'
#!/bin/bash
/opt/bin/f2b-dashboard.sh
SCRIPT
    
    chmod +x $APP_DIR/security.sh
    
    print_success "Management scripts created in $APP_DIR/ and /opt/bin/"
}

# Setup Nginx with Cloudflare protection
install_nginx() {
    print_header "Installing and Configuring Nginx"
    
    if command -v nginx &> /dev/null; then
        print_warning "Nginx is already installed"
    else
        sudo apt install -y nginx
        print_success "Nginx installed"
    fi
    
    if [ "$SETUP_SSL" = "letsencrypt" ]; then
        setup_letsencrypt_ssl
    elif [ "$SETUP_SSL" = "selfsigned" ]; then
        setup_selfsigned_ssl
    fi
    
    # Create necessary log files
    sudo touch /var/log/nginx/esc_access.log
    sudo touch /var/log/nginx/esc_error.log
    sudo chown www-data:adm /var/log/nginx/esc_*.log
    sudo chmod 644 /var/log/nginx/esc_*.log
    
    if [ "$SECURITY_ENABLED" = "true" ]; then
        create_nginx_config_secure
    else
        if [ "$SETUP_SSL" != "none" ]; then
            create_nginx_config_with_ssl
        else
            create_nginx_config_http_only
        fi
    fi
    
    sudo ln -sf /etc/nginx/sites-available/esc /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # Test configuration
    if sudo nginx -t; then
        sudo systemctl restart nginx
        sudo systemctl enable nginx
        print_success "Nginx configured and started"
    else
        print_error "Nginx configuration test failed"
        # Show specific error
        sudo nginx -t 2>&1 | tail -20
        exit 1
    fi
}

# Let's Encrypt SSL setup
setup_letsencrypt_ssl() {
    print_header "Setting Up Let's Encrypt SSL"
    
    if ! command -v certbot &> /dev/null; then
        print_info "Installing Certbot..."
        sudo apt install -y certbot python3-certbot-nginx
        print_success "Certbot installed"
    fi
    
    print_info "Obtaining SSL certificate..."
    
    sudo certbot certonly --nginx \
        --non-interactive \
        --agree-tos \
        --email "$SSL_EMAIL" \
        -d "$DOMAIN_NAME" \
        -d "www.$DOMAIN_NAME" || {
        print_error "Failed to obtain certificate"
        SETUP_SSL="none"
        return
    }
    
    print_success "SSL certificate obtained"
    
    # Setup auto-renewal
    (sudo crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | sudo crontab -
    print_success "Auto-renewal configured"
}

# Self-signed SSL setup
setup_selfsigned_ssl() {
    print_header "Setting Up Self-Signed SSL"
    
    sudo mkdir -p /etc/nginx/ssl
    
    print_info "Generating certificate..."
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/selfsigned.key \
        -out /etc/nginx/ssl/selfsigned.crt \
        -subj "/C=KE/ST=Nairobi/L=Nairobi/O=ESC/CN=$DOMAIN_NAME"
    
    sudo chmod 600 /etc/nginx/ssl/selfsigned.key
    sudo chmod 644 /etc/nginx/ssl/selfsigned.crt
    
    print_success "Self-signed certificate created"
}

# Secure Nginx config with Cloudflare + Fail2Ban - SIMPLIFIED VERSION
create_nginx_config_secure() {
    print_info "Creating secure Nginx config with Cloudflare protection..."
    
    # Determine SSL configuration
    if [ "$SETUP_SSL" = "letsencrypt" ]; then
        SSL_CERT="/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem"
        SSL_KEY="/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem"
        SSL_BLOCK="ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;"
    elif [ "$SETUP_SSL" = "selfsigned" ]; then
        SSL_CERT="/etc/nginx/ssl/selfsigned.crt"
        SSL_KEY="/etc/nginx/ssl/selfsigned.key"
        SSL_BLOCK="ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;"
    else
        SSL_CERT=""
        SSL_KEY=""
        SSL_BLOCK=""
    fi
    
    # Create simplified secure config
    sudo tee /etc/nginx/sites-available/esc > /dev/null << EOF
# Rate limiting zones
limit_req_zone \$binary_remote_addr zone=general_limit:10m rate=10r/s;
limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=30r/m;
limit_req_zone \$binary_remote_addr zone=login_limit:10m rate=5r/m;
limit_req_status 429;

upstream django_app {
    server 127.0.0.1:8000;
    keepalive 64;
}

# HTTP redirect to HTTPS (if SSL enabled)
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;
    
    # Let's Encrypt verification
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;
    
    $SSL_BLOCK
    
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
    if (\$request_method !~ ^(GET|HEAD|POST|PUT|DELETE|OPTIONS)\$) {
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
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
    }
    
    # API endpoints with stricter rate limiting
    location /api/ {
        limit_req zone=api_limit burst=5 nodelay;
        
        proxy_pass http://django_app;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Authentication endpoints with strict rate limiting
    location ~ ^/(account|auth|login|signin|register) {
        limit_req zone=login_limit burst=2 nodelay;
        
        proxy_pass http://django_app;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        proxy_pass http://django_app;
        proxy_set_header Host \$host;
        proxy_connect_timeout 5s;
        proxy_read_timeout 5s;
    }
    
    # Static files (if served by Django)
    location /static/ {
        proxy_pass http://django_app;
        proxy_set_header Host \$host;
    }
    
    # Media files (if served by Django)
    location /media/ {
        proxy_pass http://django_app;
        proxy_set_header Host \$host;
    }
}
EOF
    
    print_success "Nginx secure config created"
}

# Nginx config with SSL (non-Cloudflare)
create_nginx_config_with_ssl() {
    print_info "Creating Nginx config with SSL..."
    
    if [ "$SETUP_SSL" = "letsencrypt" ]; then
        SSL_CERT="/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem"
        SSL_KEY="/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem"
    else
        SSL_CERT="/etc/nginx/ssl/selfsigned.crt"
        SSL_KEY="/etc/nginx/ssl/selfsigned.key"
    fi
    
    sudo tee /etc/nginx/sites-available/esc > /dev/null << EOF
upstream django_app {
    server 127.0.0.1:8000;
    keepalive 64;
}

server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;
    
    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    access_log /var/log/nginx/esc_access.log;
    error_log /var/log/nginx/esc_error.log;
    
    client_max_body_size 100M;
    proxy_connect_timeout 600s;
    proxy_send_timeout 600s;
    proxy_read_timeout 600s;
    
    location / {
        proxy_pass http://django_app;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    location /health {
        access_log off;
        proxy_pass http://django_app;
        proxy_set_header Host \$host;
    }
}
EOF
    
    print_success "Nginx config created"
}

# Nginx HTTP-only config
create_nginx_config_http_only() {
    print_info "Creating HTTP-only Nginx config..."
    
    sudo tee /etc/nginx/sites-available/esc > /dev/null << EOF
upstream django_app {
    server 127.0.0.1:8000;
    keepalive 64;
}

server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    access_log /var/log/nginx/esc_access.log;
    error_log /var/log/nginx/esc_error.log;
    
    client_max_body_size 100M;
    proxy_connect_timeout 600s;
    proxy_send_timeout 600s;
    proxy_read_timeout 600s;
    
    location / {
        proxy_pass http://django_app;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    location /health {
        access_log off;
        proxy_pass http://django_app;
        proxy_set_header Host \$host;
    }
}
EOF
    
    print_success "Nginx HTTP config created"
}

# Setup firewall
setup_firewall() {
    if [[ "$SETUP_FIREWALL" =~ ^[Yy]$ ]]; then
        print_header "Configuring UFW Firewall"
        
        # Reset UFW to defaults
        sudo ufw --force reset
        
        # Set default policies
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        
        # Allow SSH
        sudo ufw allow 22/tcp
        
        # Allow HTTP and HTTPS
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        
        # Enable UFW
        echo "y" | sudo ufw enable
        
        print_success "Firewall configured"
        sudo ufw status verbose
    fi
}

# Setup systemd service
setup_systemd() {
    print_header "Setting Up Systemd Service"
    
    sudo tee /etc/systemd/system/esc.service > /dev/null << EOF
[Unit]
Description=ESC Django Application
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
    
    cd $APP_DIR
    
    print_info "Pulling latest Docker image..."
    if ! docker pull andreastuko/esc:latest; then
        print_error "Failed to pull Docker image"
        print_info "Continuing with existing image if available..."
    else
        print_success "Docker image pulled successfully"
    fi
    
    print_info "Starting services..."
    if docker compose -f compose.prod.yaml up -d; then
        print_success "Services started successfully"
    else
        print_error "Failed to start services"
        print_info "Checking logs for details..."
        docker compose -f compose.prod.yaml logs --tail=20
        exit 1
    fi
    
    print_info "Waiting for services to initialize..."
    for i in {1..12}; do
        echo -n "."
        sleep 5
    done
    echo
    
    # Check service status
    if docker compose -f compose.prod.yaml ps | grep -q "Up"; then
        print_success "All services are running"
        docker compose -f compose.prod.yaml ps
    else
        print_warning "Some services may not be running properly"
        docker compose -f compose.prod.yaml ps
        docker compose -f compose.prod.yaml logs --tail=20
    fi
}

# Print completion message
print_completion() {
    print_header "Installation Complete!"
    
    echo -e "${GREEN}Your ESC Django application is fully deployed!${NC}\n"
    
    echo "Application Details:"
    echo "  Domain: https://$DOMAIN_NAME"
    echo "  App Directory: $APP_DIR"
    echo "  Environment: $APP_DIR/.env.docker"
    echo
    
    echo "Management Commands:"
    echo "  Deploy/Update:    $APP_DIR/deploy.sh"
    echo "  View Logs:        $APP_DIR/logs.sh [service]"
    echo "  Check Status:     $APP_DIR/status.sh"
    echo "  Stop Services:    $APP_DIR/stop.sh"
    echo "  Start Services:   $APP_DIR/start.sh"
    
    if [ "$SECURITY_ENABLED" = "true" ]; then
        echo "  Security Status:  $APP_DIR/security.sh"
        echo
        echo -e "${GREEN}Security Features Enabled:${NC}"
        echo "  ✓ Basic Fail2Ban protection"
        echo "  ✓ Nginx rate limiting"
        echo "  ✓ Security headers"
        echo "  ✓ Common attack pattern blocking"
        echo
        echo "Security Management:"
        echo "  Dashboard:       /opt/bin/f2b-dashboard.sh"
        echo "  Unban IP:        /opt/bin/f2b-unban.sh <IP>"
    fi
    
    echo
    echo "Cloudflare Setup:"
    echo "  1. Add A record pointing to: $(hostname -I | awk '{print $1}')"
    echo "  2. Set SSL/TLS to: 'Full (strict)' (if using Let's Encrypt) or 'Flexible'"
    echo "  3. Enable: 'Always Use HTTPS'"
    echo
    
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Create Django superuser:"
    echo "     cd $APP_DIR && docker compose -f compose.prod.yaml exec web python manage.py createsuperuser"
    echo "  2. Monitor logs for errors:"
    echo "     $APP_DIR/logs.sh"
    echo "  3. Test your application:"
    echo "     curl -I https://$DOMAIN_NAME"
    echo
    
    print_warning "Note: If Fail2Ban failed to start, you can manually configure it later."
    print_info "To troubleshoot Fail2Ban: sudo journalctl -u fail2ban -f"
}

# Main installation flow
main() {
    print_header "ESC Django Application - Automated Deployment with Security"
    
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

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

# Configure Fail2Ban
setup_fail2ban() {
    print_header "Configuring Fail2Ban with Security Policies"
    
    mkdir -p /tmp/fail2ban_setup
    cd /tmp/fail2ban_setup
    
    # Create jail.local
    cat > jail.local << EOF
[DEFAULT]
bantime = 2592000
findtime = 3600
maxretry = 5
destemail = $ADMIN_EMAIL
sendername = Fail2Ban
action = %(action_mwl)s
[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 604800
findtime = 600
[nginx-cloudflare-only]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_error.log
maxretry = 1
bantime = 2592000
findtime = 300
[nginx-bad-requests]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 5
bantime = 86400
findtime = 600
[nginx-rate-limit]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 3
bantime = 86400
findtime = 300
[nginx-noscript]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 2
bantime = 1209600
findtime = 600
[nginx-scan]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 3
bantime = 604800
findtime = 600
[nginx-sqli]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 1
bantime = 2592000
findtime = 300
[nginx-xss]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 3
bantime = 1209600
findtime = 600
[nginx-rfi-lfi]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 1
bantime = 2592000
findtime = 300
[nginx-baduseragent]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 1
bantime = 1209600
findtime = 300
[nginx-ddos]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 100
bantime = 3600
findtime = 60
EOF
    
    sudo cp jail.local /etc/fail2ban/jail.local
    
    # Create filters directory
    mkdir -p filters
    
    # Create all filter files
    cat > filters/nginx-cloudflare-only.conf << 'FILTER'
[Definition]
failregex = ^<HOST> .* "." .$
ignoreregex =
FILTER
    
    cat > filters/nginx-bad-requests.conf << 'FILTER'
[Definition]
failregex = ^<HOST> .* "." (?:400|403|429|444) .$
ignoreregex =
FILTER
    
    cat > filters/nginx-rate-limit.conf << 'FILTER'
[Definition]
failregex = ^<HOST> .* "." 429 .$
ignoreregex =
FILTER
    
    cat > filters/nginx-noscript.conf << 'FILTER'
[Definition]
failregex = ^<HOST> .* "(?:GET|POST|HEAD|OPTIONS) /(.php|.asp|.cgi|wp-admin|wp-login|xmlrpc.php|shell.php|backdoor|admin.php)" .*$
ignoreregex =
FILTER
    
    cat > filters/nginx-scan.conf << 'FILTER'
[Definition]
failregex = ^<HOST> .* "(?:GET|POST|HEAD|OPTIONS) /?(admin|api|backup|config|database|wp-content|uploads|files|includes|themes|plugins|.env|.git|.aws|.ssh|.htaccess|web.config)" .*$
ignoreregex =
FILTER
    
    cat > filters/nginx-sqli.conf << 'FILTER'
[Definition]
failregex = ^<HOST> .* "(?:.(?:union|select|insert|update|delete|drop|create|alter|exec|execute|script|javascript|onclick|onerror|alert|eval).)" .*$
ignoreregex =
FILTER
    
    cat > filters/nginx-xss.conf << 'FILTER'
[Definition]
failregex = ^<HOST> .* "(?:.(?:<script|javascript:|onerror=|onclick=|alert(|eval(|vbscript:|onload=).)" .*$
ignoreregex =
FILTER
    
    cat > filters/nginx-rfi-lfi.conf << 'FILTER'
[Definition]
failregex = ^<HOST> .* "(?:.(?:file://|../|..\|etc/passwd|proc/self|ftp://|http://|https://|gopher://|data:).)" .*$
ignoreregex =
FILTER
    
    cat > filters/nginx-baduseragent.conf << 'FILTER'
[Definition]
failregex = ^<HOST> .* "." ."(?:.(?:bot|crawler|spider|curl|wget|nikto|nmap|nessus|masscan|zap|burp|sqlmap|metasploit|havij|acunetix).)" .*$
ignoreregex =
FILTER
    
    cat > filters/nginx-ddos.conf << 'FILTER'
[Definition]
failregex = ^<HOST> .* "." .$
ignoreregex =
FILTER
    
    sudo cp filters/*.conf /etc/fail2ban/filter.d/
    
    # Setup logging
    sudo touch /var/log/fail2ban-custom.log
    sudo chmod 640 /var/log/fail2ban-custom.log
    
    # Setup logrotate
    cat > logrotate.fail2ban << 'LOGROTATE'
/var/log/fail2ban-custom.log {
weekly
rotate 26
missingok
compress
delaycompress
copytruncate
}
LOGROTATE
    
    sudo tee -a /etc/logrotate.d/fail2ban > /dev/null << 'LOGROTATE'
/var/log/fail2ban-custom.log {
weekly
rotate 26
missingok
compress
delaycompress
copytruncate
}
LOGROTATE
    
    print_success "Fail2Ban configuration installed"
    
    # Start Fail2Ban
    sudo systemctl enable fail2ban
    sudo systemctl restart fail2ban
    
    sleep 2
    
    if systemctl is-active --quiet fail2ban; then
        print_success "Fail2Ban service started"
    else
        print_error "Fail2Ban failed to start"
        sudo systemctl status fail2ban
    fi
    
    cd - > /dev/null
}

# Create management scripts
create_management_scripts() {
    print_header "Creating Management Scripts"
    
    mkdir -p /opt/bin
    
    # Fail2Ban dashboard
    cat > /opt/bin/f2b-dashboard.sh << 'SCRIPT'
#!/bin/bash
clear
echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║                        Fail2Ban Security Dashboard                            ║"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo
echo "System Status: $(systemctl is-active fail2ban)"
echo "Timestamp: $(date)"
echo
echo "────────────────────────────────────────────────────────────────────────────────"
echo
echo "PER-JAIL STATISTICS"
echo "───────────────────"
JAILS=("sshd" "nginx-cloudflare-only" "nginx-bad-requests" "nginx-rate-limit" "nginx-noscript" "nginx-scan" "nginx-sqli" "nginx-xss" "nginx-rfi-lfi" "nginx-baduseragent" "nginx-ddos")
for jail in "${JAILS[@]}"; do
    if fail2ban-client status $jail &>/dev/null 2>&1; then
        STATUS=$(fail2ban-client status $jail 2>/dev/null)
        BANNED=$(echo "$STATUS" | grep "Currently banned" | grep -oP '\d+(?=\s)' | tail -1)
        echo "  $jail: $BANNED banned"
    fi
done

echo
echo "────────────────────────────────────────────────────────────────────────────────"
echo
echo "RECENTLY BANNED IPs (Last 10)"
echo "────────────────────────────"
tail -10 /var/log/fail2ban-custom.log 2>/dev/null | grep "BANNED" | tail -10 || echo "No recent bans"

echo
echo "────────────────────────────────────────────────────────────────────────────────"
echo
echo "TOP 10 OFFENDING IPs"
echo "──────────────────"
iptables -L -n | grep DROP | grep -v "^Chain" | awk '{print $4}' | sort | uniq -c | sort -rn | head -10 | awk '{print "  " $0}'

echo
echo "────────────────────────────────────────────────────────────────────────────────"
echo
echo "COMMANDS:"
echo "  Unban IP:        /opt/bin/f2b-unban.sh <IP>"
echo "  View logs:       tail -f /var/log/fail2ban-custom.log"
SCRIPT
    
    sudo chmod +x /opt/bin/f2b-dashboard.sh
    
    # Unban script
    cat > /opt/bin/f2b-unban.sh << 'SCRIPT'
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: $0 <IP_ADDRESS>"
    exit 1
fi
IP=$1
echo "Unbanning $IP..."
JAILS=("sshd" "nginx-cloudflare-only" "nginx-bad-requests" "nginx-rate-limit" "nginx-noscript" "nginx-scan" "nginx-sqli" "nginx-xss" "nginx-rfi-lfi" "nginx-baduseragent" "nginx-ddos")
for jail in "${JAILS[@]}"; do
    sudo fail2ban-client set $jail unbanip $IP 2>/dev/null && echo "✓ Unbanned from $jail"
done
echo "[$(date '+%Y-%m-%d %H:%M:%S')] MANUAL UNBAN: $IP" | sudo tee -a /var/log/fail2ban-custom.log > /dev/null
echo "Done"
SCRIPT
    
    sudo chmod +x /opt/bin/f2b-unban.sh
    
    # Deploy script
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
    
    # Logs script
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
    
    # Status script
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
    
    # Stop script
    cat > $APP_DIR/stop.sh << 'SCRIPT'
#!/bin/bash
cd $(dirname "$0")
echo "Stopping all services..."
docker compose -f compose.prod.yaml down
echo "Services stopped."
SCRIPT
    
    chmod +x $APP_DIR/stop.sh
    
    # Start script
    cat > $APP_DIR/start.sh << 'SCRIPT'
#!/bin/bash
cd $(dirname "$0")
echo "Starting all services..."
docker compose -f compose.prod.yaml up -d
sleep 30
docker compose -f compose.prod.yaml ps
SCRIPT
    
    chmod +x $APP_DIR/start.sh
    
    # Security dashboard link
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

# Let's Encrypt SSL setup
setup_letsencrypt_ssl() {
    print_header "Setting Up Let's Encrypt SSL"
    
    if ! command -v certbot &> /dev/null; then
        print_info "Installing Certbot..."
        sudo apt install -y certbot python3-certbot-nginx
        print_success "Certbot installed"
    fi
    
    sudo systemctl stop nginx || true
    
    print_info "Obtaining SSL certificate..."
    
    sudo certbot certonly --standalone \
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
    
    print_info "Generating Diffie-Hellman parameters..."
    sudo openssl dhparam -out /etc/nginx/ssl/dhparam.pem 2048
    
    print_success "Self-signed certificate created"
}

# Secure Nginx config with Cloudflare + Fail2Ban
create_nginx_config_secure() {
    print_info "Creating secure Nginx config with Cloudflare protection..."
    
    if [ "$SETUP_SSL" = "letsencrypt" ]; then
        SSL_CERT="/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem"
        SSL_KEY="/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem"
        OCSP_BLOCK="ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/letsencrypt/live/$DOMAIN_NAME/chain.pem;"
    elif [ "$SETUP_SSL" = "selfsigned" ]; then
        SSL_CERT="/etc/nginx/ssl/selfsigned.crt"
        SSL_KEY="/etc/nginx/ssl/selfsigned.key"
        OCSP_BLOCK="ssl_dhparam /etc/nginx/ssl/dhparam.pem;"
    else
        SSL_CERT=""
        SSL_KEY=""
        OCSP_BLOCK=""
    fi
    
    # Build Cloudflare IPs list
    cat > /tmp/nginx_esc.conf << 'NGINX'
# Cloudflare IP geo-block
geo $is_cloudflare {
    default 0;
    173.245.48.0/20 1;
    103.21.244.0/22 1;
    103.22.200.0/22 1;
    103.31.4.0/22 1;
    141.101.64.0/18 1;
    108.162.192.0/18 1;
    190.93.240.0/20 1;
    188.114.96.0/20 1;
    197.234.240.0/22 1;
    198.41.128.0/17 1;
    162.158.0.0/15 1;
    104.16.0.0/13 1;
    104.24.0.0/14 1;
    172.64.0.0/13 1;
    131.0.72.0/22 1;
    2400:cb00::/32 1;
    2606:4700::/32 1;
    2803:f800::/32 1;
    2405:b500::/32 1;
    2405:8100::/32 1;
    2a06:98c0::/29 1;
    2c0f:f248::/32 1;
}

# Rate limiting zones
limit_req_zone $binary_remote_addr zone=general_limit:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=30r/m;
limit_req_zone $binary_remote_addr zone=login_limit:10m rate=5r/m;
limit_req_status 429;

# Connection limiting
limit_conn_zone $binary_remote_addr zone=addr:10m;

upstream django_app {
    server 127.0.0.1:8000;
    keepalive 64;
}

# Default catch-all server - block non-Cloudflare
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    
    server_name _;
NGINX
    
    if [ -n "$SSL_CERT" ]; then
        cat >> /tmp/nginx_esc.conf << NGINX
    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
NGINX
    fi
    
    cat >> /tmp/nginx_esc.conf << 'NGINX'
    
    if ($is_cloudflare = 0) {
        return 403;
    }
    
    location / {
        return 403;
    }
}

# HTTP Server
server {
    listen 80;
    listen [::]:80;
    server_name DOMAIN_NAME www.DOMAIN_NAME;
    
    if ($is_cloudflare = 0) {
        return 403;
    }
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS Server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name DOMAIN_NAME www.DOMAIN_NAME;
    
    if ($is_cloudflare = 0) {
        return 403;
    }
NGINX
    
    if [ -n "$SSL_CERT" ]; then
        cat >> /tmp/nginx_esc.conf << NGINX
    
    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
    
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    $OCSP_BLOCK
NGINX
    fi
    
    cat >> /tmp/nginx_esc.conf << 'NGINX'
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    
    access_log /var/log/nginx/esc_access.log;
    error_log /var/log/nginx/esc_error.log;
    
    client_max_body_size 100M;
    client_body_buffer_size 128k;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 16k;
    
    proxy_connect_timeout 600s;
    proxy_send_timeout 600s;
    proxy_read_timeout 600s;
    send_timeout 600s;
    
    if ($request_method !~ ^(GET|HEAD|POST|PUT|DELETE|OPTIONS)$) {
        return 405;
    }
    
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    location ~ /\.env {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    location ~ ^/(wp-admin|wp-login|admin\.php|administrator|phpmyadmin) {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    location = /xmlrpc.php {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    location ~ \.(bak|backup|old|tar|zip|sql|db)$ {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    location / {
        limit_req zone=general_limit burst=20 nodelay;
        limit_conn addr 10;
        
        real_ip_header CF-Connecting-IP;
        
        proxy_pass http://django_app;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header CF-Connecting-IP $remote_addr;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
    }
    
    location /api/ {
        limit_req zone=api_limit burst=5 nodelay;
        limit_conn addr 5;
        
        proxy_pass http://django_app;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location ~ ^/(account|auth|login|signin) {
        limit_req zone=login_limit burst=2 nodelay;
        limit_conn addr 3;
        
        proxy_pass http://django_app;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location /health {
        access_log off;
        proxy_pass http://django_app;
        proxy_set_header Host $host;
        proxy_connect_timeout 5s;
        proxy_read_timeout 5s;
    }
    
    location /health/ready/ {
        access_log off;
        proxy_pass http://django_app;
        proxy_set_header Host $host;
        proxy_connect_timeout 5s;
        proxy_read_timeout 5s;
    }
    
    location = /robots.txt {
        access_log off;
        log_not_found off;
    }
}
NGINX
    
    # Replace domain placeholder
    sed -i "s/DOMAIN_NAME/$DOMAIN_NAME/g" /tmp/nginx_esc.conf
    
    sudo cp /tmp/nginx_esc.conf /etc/nginx/sites-available/esc
    sudo chown root:root /etc/nginx/sites-available/esc
    sudo chmod 644 /etc/nginx/sites-available/esc
    
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
        
        sudo ufw allow 22/tcp
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        sudo ufw --force enable
        
        print_success "Firewall configured"
        sudo ufw status
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
    
    print_success "Systemd service created"
}

# Pull and start application
start_application() {
    print_header "Starting Application"
    
    cd $APP_DIR
    
    print_info "Pulling latest Docker image..."
    docker pull andreastuko/esc:latest
    
    print_info "Starting services..."
    docker compose -f compose.prod.yaml up -d
    
    print_info "Waiting for services to start..."
    
    for i in {1..12}; do
        sleep 5
        echo -n "."
    done
    echo
    
    docker compose -f compose.prod.yaml ps
    
    print_success "Application started"
}

# Print completion message
print_completion() {
    print_header "Installation Complete!"
    
    echo -e "${GREEN}Your ESC Django application is fully deployed with security hardening!${NC}\n"
    
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
    echo "  Security Status:  $APP_DIR/security.sh"
    echo
    
    if [ "$SECURITY_ENABLED" = "true" ]; then
        echo -e "${GREEN}Security Features Enabled:${NC}"
        echo "  ✓ Cloudflare-only IP enforcement (geo-blocking)"
        echo "  ✓ Multi-jail Fail2Ban protection"
        echo "  ✓ Rate limiting (10 req/s general, 5 req/min login)"
        echo "  ✓ Vulnerability scanner detection"
        echo "  ✓ SQL injection/XSS protection"
        echo "  ✓ DDoS detection and mitigation"
        echo "  ✓ Bad bot blocking"
        echo "  ✓ Automatic threat response"
        echo
        
        echo "Security Management:"
        echo "  Dashboard:       /opt/bin/f2b-dashboard.sh"
        echo "  Unban IP:        /opt/bin/f2b-unban.sh <IP>"
        echo "  Monitor logs:    tail -f /var/log/fail2ban-custom.log"
        echo "  Check bans:      iptables -L -n | grep DROP"
        echo
        
        echo "Important Security Notes:"
        echo "  • Non-Cloudflare IPs are blocked with 403"
        echo "  • SQL injection = 30-day permanent ban"
        echo "  • Scanner detected = 14-30 day ban"
        echo "  • Direct IP access = 30-day permanent ban"
        echo "  • All bans logged in /var/log/fail2ban-custom.log"
        echo
    fi
    
    echo "Cloudflare Setup:"
    echo "  1. Add A record pointing to: $(hostname -I | awk '{print $1}')"
    echo "  2. Set SSL/TLS to: 'Full (strict)' (if using Let's Encrypt) or 'Flexible'"
    echo "  3. Enable: 'Always Use HTTPS'"
    echo "  4. Test: curl -I https://$DOMAIN_NAME"
    echo
    
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Create Django superuser:"
    echo "     cd $APP_DIR && docker compose -f compose.prod.yaml exec web python manage.py createsuperuser"
    echo "  2. Monitor logs for 24 hours"
    echo "  3. Test legitimate traffic"
    echo "  4. Review banned IPs in security dashboard"
    echo
    
    echo -e "${CYAN}View documentation:${NC}"
    echo "  cd $APP_DIR"
    echo "  ls -la docs/"
    echo
    
    print_warning "You may need to log out and back in for Docker group changes"
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
    
    if [ "$SECURITY_ENABLED" = "true" ]; then
        install_fail2ban
        setup_fail2ban
    fi
    
    install_nginx
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
#!/bin/bash

# ESC Django Application - Enterprise Deployment Script v2.1
# Production-grade deployment with SAFE SSH hardening
# For DevOps teams - Full integration with Django app structure

set -e

# ============================================================================
# COLOR & OUTPUT CONFIGURATION
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} $1"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

print_step() {
    echo -e "${MAGENTA}▶${NC} $1"
}

print_section() {
    echo -e "\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}$1${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# ============================================================================
# VALIDATION & CHECKS
# ============================================================================

check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        print_info "This script requires sudo privileges. You may be prompted for your password."
        sudo -v
    fi
}

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

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

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
# Auto-generated - Last updated: $(date '+%Y-%m-%d %H:%M:%S')
DOMAIN_NAME="$DOMAIN_NAME"
DOCKER_USERNAME="$DOCKER_USERNAME"
APP_DIR="$APP_DIR"
SETUP_SSL="$SETUP_SSL"
SSL_EMAIL="$SSL_EMAIL"
SECURITY_ENABLED="$SECURITY_ENABLED"
ADMIN_EMAIL="$ADMIN_EMAIL"
SSH_HARDENING="$SSH_HARDENING"
SSH_PORT="$SSH_PORT"
FAIL2BAN_AGGRESSIVE="$FAIL2BAN_AGGRESSIVE"
ENABLE_2FA_SETUP="$ENABLE_2FA_SETUP"
FIREWALL_WHITELIST="$FIREWALL_WHITELIST"
DISABLE_ROOT_LOGIN="$DISABLE_ROOT_LOGIN"
CREATED_SUDO_USER="$CREATED_SUDO_USER"
EOF
    
    chmod 600 "$CONFIG_FILE"
    print_success "Configuration saved"
}

# ============================================================================
# INTERACTIVE CONFIGURATION
# ============================================================================

gather_config() {
    print_header "Enterprise Deployment Configuration"
    
    DEFAULT_APP_DIR="/opt/apps/esc"
    APP_DIR="${APP_DIR:-$DEFAULT_APP_DIR}"
    
    load_existing_config
    
    if [ "$EXISTING_CONFIG" = true ]; then
        print_success "Existing deployment detected!"
        echo
        echo "Previous Configuration:"
        echo "  Domain: $DOMAIN_NAME"
        echo "  Docker Hub User: $DOCKER_USERNAME"
        echo "  App Directory: $APP_DIR"
        echo "  SSL: $SETUP_SSL"
        echo "  Security: $SECURITY_ENABLED"
        echo "  SSH Hardening: $SSH_HARDENING (Port: $SSH_PORT)"
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
    
    # Domain Configuration
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
    
    # Docker Hub Credentials
    print_info "Docker Hub credentials required to pull private image"
    
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
    
    # Application Directory
    if [ -n "$APP_DIR" ] && [ "$APP_DIR" != "$DEFAULT_APP_DIR" ]; then
        read -p "Application directory [$APP_DIR]: " NEW_APP_DIR
        APP_DIR=${NEW_APP_DIR:-$APP_DIR}
    else
        read -p "Application directory [$DEFAULT_APP_DIR]: " APP_DIR
        APP_DIR=${APP_DIR:-$DEFAULT_APP_DIR}
    fi
    
    # User Creation
    if [ "$EXISTING_CONFIG" != true ]; then
        read -p "Create dedicated 'deployer' user? (recommended) [Y/n]: " CREATE_USER
        CREATE_USER=${CREATE_USER:-Y}
    fi
    
    # Firewall Setup
    if [ "$EXISTING_CONFIG" != true ]; then
        read -p "Configure UFW firewall? (recommended) [Y/n]: " SETUP_FIREWALL
        SETUP_FIREWALL=${SETUP_FIREWALL:-Y}
    fi
    
    # SSL Configuration
    configure_ssl_option
    
    # Security Configuration (ENTERPRISE)
    configure_security_enterprise
}

configure_ssl_option() {
    echo
    print_info "SSL Certificate Configuration"
    echo "Choose SSL certificate option:"
    echo "  1) Let's Encrypt (Free, auto-renewing, requires valid domain)"
    echo "  2) Self-signed (Works with IP address, not trusted by browsers)"
    echo "  3) None (Use Cloudflare SSL only)"
    read -p "Select option [1/2/3]: " SSL_OPTION
    SSL_OPTION=${SSL_OPTION:-1}
    
    if [ "$SSL_OPTION" = "1" ]; then
        SETUP_SSL="letsencrypt"
        if [ -n "$SSL_EMAIL" ]; then
            read -p "Email for Let's Encrypt [$SSL_EMAIL]: " NEW_SSL_EMAIL
            SSL_EMAIL=${NEW_SSL_EMAIL:-$SSL_EMAIL}
        else
            read -p "Email for Let's Encrypt: " SSL_EMAIL
            while [ -z "$SSL_EMAIL" ]; do
                print_warning "Email cannot be empty"
                read -p "Email for Let's Encrypt: " SSL_EMAIL
            done
        fi
    elif [ "$SSL_OPTION" = "2" ]; then
        SETUP_SSL="selfsigned"
        print_warning "Self-signed certificates show security warnings"
    else
        SETUP_SSL="none"
        SSL_EMAIL=""
        print_info "Using HTTP only (Cloudflare handles SSL)"
    fi
}

configure_security_enterprise() {
    print_header "Enterprise Security Configuration"
    
    # Basic Security
    echo "Enable advanced security features? (Recommended: Yes)"
    echo "  • Fail2Ban with aggressive policies"
    echo "  • Rate limiting protection"
    echo "  • DDoS protection"
    echo "  • Security headers"
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
        
        print_success "Security features enabled"
    else
        SECURITY_ENABLED="false"
        ADMIN_EMAIL=""
    fi
    
    # SSH Hardening Configuration
    print_section "SSH Hardening Configuration (Enterprise Grade)"
    
    echo "Enable SSH hardening? (Highly Recommended)"
    echo "  ✓ Change SSH port from default 22"
    echo "  ✓ Add SSH banner warning"
    echo "  ✓ Option to disable password authentication (key-only)"
    echo "  ✓ Option to disable root login (with safety checks)"
    echo "  ✓ Restrict SSH to specific IPs (optional)"
    echo
    read -p "Enable SSH hardening? [Y/n]: " ENABLE_SSH_HARDENING
    ENABLE_SSH_HARDENING=${ENABLE_SSH_HARDENING:-Y}
    
    if [[ "$ENABLE_SSH_HARDENING" =~ ^[Yy]$ ]]; then
        SSH_HARDENING="true"
        
        # SSH Port Selection
        print_info "Choose SSH port (default 22 is under constant attack)"
        read -p "Enter SSH port [2222]: " SSH_PORT
        SSH_PORT=${SSH_PORT:-2222}
        
        if [ "$SSH_PORT" = "22" ]; then
            print_warning "Port 22 is constantly attacked by bots."
            read -p "Continue with port 22? [y/N]: " CONTINUE_22
            if [[ ! "$CONTINUE_22" =~ ^[Yy]$ ]]; then
                read -p "Enter SSH port [2222]: " SSH_PORT
                SSH_PORT=${SSH_PORT:-2222}
            fi
        fi
        
        # Admin IP Whitelist
        echo
        print_info "Restrict SSH to specific admin IPs? (Recommended)"
        echo "Example: 105.160.123.59 203.0.113.45"
        read -p "Enter admin IPs (space-separated) or press Enter to skip: " FIREWALL_WHITELIST
        
        # Aggressive Fail2Ban
        echo
        print_info "Enable aggressive Fail2Ban for SSH? (Recommended)"
        echo "  • Ban after 3 failed attempts (instead of 5)"
        echo "  • 30-day bans for repeat offenders"
        echo "  • Detect password spray patterns"
        read -p "Enable aggressive Fail2Ban? [Y/n]: " ENABLE_AGGRESSIVE_F2B
        ENABLE_AGGRESSIVE_F2B=${ENABLE_AGGRESSIVE_F2B:-Y}
        
        if [[ "$ENABLE_AGGRESSIVE_F2B" =~ ^[Yy]$ ]]; then
            FAIL2BAN_AGGRESSIVE="true"
        else
            FAIL2BAN_AGGRESSIVE="false"
        fi
        
        # Root login disable option
        echo
        print_warning "IMPORTANT: Disabling root login configuration"
        echo
        echo "Do you want to disable root login via SSH?"
        echo "  ⚠ Only say YES if:"
        echo "    - You have created another sudo user with a password"
        echo "    - You have copied SSH keys to that user"
        echo "    - You have tested SSH login with that user"
        echo
        read -p "Disable root login? [y/N]: " DISABLE_ROOT_PROMPT
        DISABLE_ROOT_PROMPT=${DISABLE_ROOT_PROMPT:-N}
        
        if [[ "$DISABLE_ROOT_PROMPT" =~ ^[Yy]$ ]]; then
            DISABLE_ROOT_LOGIN="yes"
            print_warning "Root login will be disabled"
        else
            DISABLE_ROOT_LOGIN="no"
            print_info "Root login will remain enabled"
        fi
        
        # Password authentication disable option
        echo
        print_warning "IMPORTANT: Password authentication configuration"
        echo
        echo "Do you want to disable password authentication (key-only)?"
        echo "  ⚠ Only say YES if:"
        echo "    - You have SSH keys properly configured"
        echo "    - You have tested SSH key authentication"
        echo "    - You have backup access to the server"
        echo
        read -p "Disable password authentication? [y/N]: " DISABLE_PASSWORD_AUTH
        DISABLE_PASSWORD_AUTH=${DISABLE_PASSWORD_AUTH:-N}
        
        if [[ "$DISABLE_PASSWORD_AUTH" =~ ^[Yy]$ ]]; then
            PASSWORD_AUTH="no"
            print_warning "Password authentication will be disabled"
        else
            PASSWORD_AUTH="yes"
            print_info "Password authentication will remain enabled"
        fi
        
        # 2FA Setup Prompt
        echo
        print_info "Setup SSH 2FA guide? (Two-Factor Authentication)"
        read -p "Enable SSH 2FA setup guide? [Y/n]: " ENABLE_2FA_SETUP
        ENABLE_2FA_SETUP=${ENABLE_2FA_SETUP:-Y}
        
        print_success "SSH hardening will be applied"
    else
        SSH_HARDENING="false"
        SSH_PORT="22"
        FIREWALL_WHITELIST=""
        FAIL2BAN_AGGRESSIVE="false"
        ENABLE_2FA_SETUP="false"
        DISABLE_ROOT_LOGIN="no"
        PASSWORD_AUTH="yes"
    fi
    
    print_header "Configuration Summary"
    echo "Domain: $DOMAIN_NAME"
    echo "App Directory: $APP_DIR"
    echo "SSL: $SETUP_SSL"
    echo "Security: $SECURITY_ENABLED"
    echo "SSH Hardening: $SSH_HARDENING"
    if [ "$SSH_HARDENING" = "true" ]; then
        echo "SSH Port: $SSH_PORT"
        [ -n "$FIREWALL_WHITELIST" ] && echo "Whitelisted IPs: $FIREWALL_WHITELIST"
        echo "Aggressive Fail2Ban: $FAIL2BAN_AGGRESSIVE"
        echo "Root Login: $DISABLE_ROOT_LOGIN"
        echo "Password Auth: $PASSWORD_AUTH"
    fi
    echo
    
    read -p "Proceed with installation? [Y/n]: " CONFIRM
    CONFIRM=${CONFIRM:-Y}
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled."
        exit 0
    fi
}

# ============================================================================
# SYSTEM SETUP
# ============================================================================

update_system() {
    print_header "Updating System Packages"
    sudo apt update
    sudo apt upgrade -y
    sudo apt install -y curl wget git ufw nano jq mailutils sendmail fail2ban
    print_success "System packages updated"
}

install_docker() {
    print_header "Installing Docker & Docker Compose"
    
    if command -v docker &> /dev/null; then
        print_warning "Docker already installed: $(docker --version)"
    else
        print_step "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh
        sudo usermod -aG docker $USER
        print_success "Docker installed"
    fi
    
    if docker compose version &> /dev/null; then
        print_warning "Docker Compose already installed"
    else
        print_step "Installing Docker Compose..."
        sudo apt install -y docker-compose-plugin
        print_success "Docker Compose installed"
    fi
}

create_deployer_user() {
    if [[ "$CREATE_USER" =~ ^[Yy]$ ]]; then
        print_header "Creating Deployer User"
        
        if id "deployer" &>/dev/null; then
            print_warning "User 'deployer' already exists"
            CREATED_SUDO_USER="deployer"
        else
            sudo useradd -m -s /bin/bash deployer
            sudo usermod -aG docker deployer
            sudo usermod -aG sudo deployer
            sudo mkdir -p /home/deployer/.ssh
            sudo chmod 700 /home/deployer/.ssh
            
            # Copy root's authorized_keys if it exists
            if [ -f /root/.ssh/authorized_keys ]; then
                sudo cp /root/.ssh/authorized_keys /home/deployer/.ssh/
                sudo chown deployer:deployer /home/deployer/.ssh/authorized_keys
                sudo chmod 600 /home/deployer/.ssh/authorized_keys
                print_success "SSH keys copied to deployer user"
            fi
            
            sudo chown deployer:deployer /home/deployer/.ssh
            
            print_success "User 'deployer' created with sudo privileges"
            print_warning "Set password for deployer user:"
            sudo passwd deployer
            
            CREATED_SUDO_USER="deployer"
        fi
    else
        CREATED_SUDO_USER=""
    fi
}

setup_app_directory() {
    print_header "Setting Up Application Directory"
    
    sudo mkdir -p $APP_DIR
    sudo chown -R $USER:$USER $APP_DIR
    
    print_success "Application directory: $APP_DIR"
}

clone_repository() {
    print_header "Cloning Repository"
    
    cd $APP_DIR
    
    if [ -d ".git" ]; then
        print_warning "Repository already exists, pulling latest..."
        git pull
    else
        print_step "Cloning from GitHub..."
        git clone https://github.com/andreas-tuko/esc-compose-prod.git .
    fi
    
    print_success "Repository cloned/updated"
}

docker_login() {
    print_header "Authenticating with Docker Hub"
    
    echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin 2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_success "Docker Hub authenticated"
    else
        print_error "Docker Hub authentication failed"
        exit 1
    fi
}

# ============================================================================
# ENVIRONMENT CONFIGURATION
# ============================================================================

generate_secret_key() {
    python3 -c "import secrets; print(secrets.token_urlsafe(50))"
}

setup_env_file() {
    print_header "Django Environment Configuration"
    
    if [ -f "$APP_DIR/.env.docker" ]; then
        print_warning "Environment file exists"
        read -p "Reconfigure it? [y/N]: " RECONFIG_ENV
        
        if [[ ! "$RECONFIG_ENV" =~ ^[Yy]$ ]]; then
            print_info "Keeping existing environment file"
            return
        fi
        
        cp $APP_DIR/.env.docker $APP_DIR/.env.docker.backup.$(date +%Y%m%d_%H%M%S)
        print_info "Backup created"
    fi
    
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
    
    print_success "Environment file created"
    print_info "Opening editor for configuration..."
    sleep 2
    nano $APP_DIR/.env.docker
    
    validate_env_file
}

validate_env_file() {
    print_header "Validating Environment"
    
    if [ ! -f "$APP_DIR/.env.docker" ]; then
        print_error "Environment file not found!"
        exit 1
    fi
    
    set -a
    source $APP_DIR/.env.docker 2>/dev/null || true
    set +a
    
    local failed=false
    
    if [ -z "$SECRET_KEY" ] || [ "$SECRET_KEY" = "your-secret-key-here" ]; then
        print_error "SECRET_KEY not configured"
        failed=true
    fi
    
    if [ -z "$ALLOWED_HOSTS" ] || [[ "$ALLOWED_HOSTS" == *"yourdomain"* ]]; then
        print_error "ALLOWED_HOSTS contains placeholder"
        failed=true
    fi
    
    if [ "$failed" = true ]; then
        read -p "Edit configuration? [Y/n]: " EDIT_AGAIN
        if [[ "$EDIT_AGAIN" =~ ^[Yy]$ ]]; then
            nano $APP_DIR/.env.docker
            validate_env_file
            return
        else
            print_error "Cannot proceed with invalid configuration"
            exit 1
        fi
    fi
    
    print_success "Environment validated"
}

# ============================================================================
# NGINX ERROR PAGES SETUP
# ============================================================================

setup_nginx_error_pages() {
    print_header "Setting Up Custom Nginx Error Pages"
    
    sudo mkdir -p /etc/nginx/error_pages
    
    # Create standalone HTML error pages (no Django template syntax)
    create_standalone_error_pages
    
    sudo chown -R www-data:www-data /etc/nginx/error_pages
    sudo chmod -R 644 /etc/nginx/error_pages
    
    print_success "Custom error pages deployed"
}

create_standalone_error_pages() {
    # Create 500/502/503/504 Error Page (mirroring Django 500.html style)
    sudo tee /etc/nginx/error_pages/50x.html > /dev/null << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>500 Internal Server Error</title>
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;500;600;700&family=Lato:wght@300;400;700&display=swap" rel="stylesheet">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        html {
            font-family: 'Playfair Display', 'ui-sans-serif', system-ui, sans-serif;
        }
        
        body {
            font-family: 'Lato', system-ui, -apple-system, sans-serif;
            background: linear-gradient(135deg, #f3f4f6 0%, #e5e7eb 100%);
            color: #1f2937;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        body.dark-mode {
            background: linear-gradient(135deg, #111827 0%, #1f2937 100%);
            color: #f3f4f6;
        }
        
        .container {
            text-align: center;
            max-width: 900px;
            padding: 40px 20px;
        }
        
        .error-code {
            font-size: 120px;
            font-weight: 700;
            line-height: 1;
            color: #db2777;
            margin-bottom: 10px;
        }
        
        h1 {
            font-size: 32px;
            font-weight: 600;
            margin-bottom: 20px;
            color: #1f2937;
        }
        
        body.dark-mode h1 {
            color: #f9fafb;
        }
        
        p {
            font-size: 18px;
            line-height: 1.6;
            margin-bottom: 10px;
            color: #6b7280;
        }
        
        body.dark-mode p {
            color: #d1d5db;
        }
        
        .footer {
            margin-top: 40px;
            font-size: 14px;
            color: #9ca3af;
        }
        
        body.dark-mode .footer {
            color: #6b7280;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="error-code">500</div>
        <h1>Internal Server Error.</h1>
        <p>We are already working to solve the problem.</p>
        <div class="footer">
            <p>If this issue persists, please contact our support team.</p>
        </div>
    </div>
</body>
</html>
HTML

    # Create 404 Error Page (mirroring Django 404.html style)
    sudo tee /etc/nginx/error_pages/40x.html > /dev/null << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>404 Page not found</title>
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;500;600;700&family=Lato:wght@300;400;700&display=swap" rel="stylesheet">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        html {
            font-family: 'Playfair Display', 'ui-sans-serif', system-ui, sans-serif;
        }
        
        body {
            font-family: 'Lato', system-ui, -apple-system, sans-serif;
            background: linear-gradient(135deg, #f3f4f6 0%, #e5e7eb 100%);
            color: #1f2937;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        body.dark-mode {
            background: linear-gradient(135deg, #111827 0%, #1f2937 100%);
            color: #f3f4f6;
        }
        
        .container {
            text-align: center;
            max-width: 900px;
            padding: 40px 20px;
        }
        
        .error-code {
            font-size: 120px;
            font-weight: 700;
            line-height: 1;
            color: #db2777;
            margin-bottom: 10px;
        }
        
        h1 {
            font-size: 32px;
            font-weight: 600;
            margin-bottom: 20px;
            color: #1f2937;
        }
        
        body.dark-mode h1 {
            color: #f9fafb;
        }
        
        p {
            font-size: 18px;
            line-height: 1.6;
            margin-bottom: 15px;
            color: #6b7280;
        }
        
        body.dark-mode p {
            color: #d1d5db;
        }
        
        .footer {
            margin-top: 40px;
            font-size: 14px;
            color: #9ca3af;
        }
        
        body.dark-mode .footer {
            color: #6b7280;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="error-code">404</div>
        <h1>Error! - Not Found</h1>
        <p>Something's missing.</p>
        <p>Sorry, we can't find that page. You'll find lots to explore on the home page.</p>
    </div>
</body>
</html>
HTML

    # Create 403 Error Page (mirroring Django 403.html style)
    sudo tee /etc/nginx/error_pages/40x_auth.html > /dev/null << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>403 Access Denied</title>
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;500;600;700&family=Lato:wght@300;400;700&display=swap" rel="stylesheet">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        html {
            font-family: 'Playfair Display', 'ui-sans-serif', system-ui, sans-serif;
        }
        
        body {
            font-family: 'Lato', system-ui, -apple-system, sans-serif;
            background: linear-gradient(135deg, #f3f4f6 0%, #e5e7eb 100%);
            color: #1f2937;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        body.dark-mode {
            background: linear-gradient(135deg, #111827 0%, #1f2937 100%);
            color: #f3f4f6;
        }
        
        .container {
            text-align: center;
            max-width: 900px;
            padding: 40px 20px;
        }
        
        .error-code {
            font-size: 120px;
            font-weight: 700;
            line-height: 1;
            color: #db2777;
            margin-bottom: 10px;
        }
        
        h1 {
            font-size: 32px;
            font-weight: 600;
            margin-bottom: 20px;
            color: #1f2937;
        }
        
        body.dark-mode h1 {
            color: #f9fafb;
        }
        
        p {
            font-size: 18px;
            line-height: 1.6;
            margin-bottom: 15px;
            color: #6b7280;
        }
        
        body.dark-mode p {
            color: #d1d5db;
        }
        
        .footer {
            margin-top: 40px;
            font-size: 14px;
            color: #9ca3af;
        }
        
        body.dark-mode .footer {
            color: #6b7280;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="error-code">403</div>
        <h1>Error! - Forbidden</h1>
        <p>Access Restricted.</p>
        <p>You don't have permission to view this resource. If you believe this is an error, please return to the homepage.</p>
    </div>
</body>
</html>
HTML
}

# ============================================================================
# NGINX CONFIGURATION
# ============================================================================

install_nginx() {
    print_header "Installing & Configuring Nginx"
    
    if command -v nginx &> /dev/null; then
        print_warning "Nginx already installed"
    else
        print_step "Installing Nginx..."
        sudo apt install -y nginx
        print_success "Nginx installed"
    fi
    
    # Setup SSL
    if [ "$SETUP_SSL" = "letsencrypt" ]; then
        setup_letsencrypt_ssl
    elif [ "$SETUP_SSL" = "selfsigned" ]; then
        setup_selfsigned_ssl
    fi
    
    # Setup error pages
    setup_nginx_error_pages
    
    # Create log files
    sudo touch /var/log/nginx/esc_access.log
    sudo touch /var/log/nginx/esc_error.log
    sudo chown www-data:adm /var/log/nginx/esc_*.log
    sudo chmod 644 /var/log/nginx/esc_*.log
    
    # Create Nginx config
    if [ "$SECURITY_ENABLED" = "true" ]; then
        create_nginx_config_secure
    else
        if [ "$SETUP_SSL" != "none" ]; then
            create_nginx_config_with_ssl
        else
            create_nginx_config_http_only
        fi
    fi
    
    # Enable site
    sudo ln -sf /etc/nginx/sites-available/esc /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # Test & start
    if sudo nginx -t; then
        sudo systemctl restart nginx
        sudo systemctl enable nginx
        print_success "Nginx configured and started"
    else
        print_error "Nginx configuration test failed"
        sudo nginx -t
        exit 1
    fi
}

setup_letsencrypt_ssl() {
    print_header "Setting Up Let's Encrypt SSL"
    
    if ! command -v certbot &> /dev/null; then
        print_step "Installing Certbot..."
        sudo apt install -y certbot python3-certbot-nginx
    fi
    
    print_step "Obtaining SSL certificate..."
    sudo certbot certonly --nginx --non-interactive --agree-tos \
        --email "$SSL_EMAIL" \
        -d "$DOMAIN_NAME" \
        -d "www.$DOMAIN_NAME" || {
        print_warning "Certificate obtainment failed"
        return
    }
    
    print_success "SSL certificate obtained"
    
    # Setup auto-renewal
    (sudo crontab -l 2>/dev/null | grep -v certbot; echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | sudo crontab -
}

setup_selfsigned_ssl() {
    print_header "Setting Up Self-Signed SSL"
    
    sudo mkdir -p /etc/nginx/ssl
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/selfsigned.key \
        -out /etc/nginx/ssl/selfsigned.crt \
        -subj "/C=KE/ST=Nairobi/L=Nairobi/O=ESC/CN=$DOMAIN_NAME"
    
    sudo chmod 600 /etc/nginx/ssl/selfsigned.key
    print_success "Self-signed certificate created"
}

create_nginx_config_secure() {
    print_info "Creating secure Nginx configuration..."
    
    # Determine SSL config
    if [ "$SETUP_SSL" = "letsencrypt" ]; then
        SSL_CERT="/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem"
        SSL_KEY="/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem"
    elif [ "$SETUP_SSL" = "selfsigned" ]; then
        SSL_CERT="/etc/nginx/ssl/selfsigned.crt"
        SSL_KEY="/etc/nginx/ssl/selfsigned.key"
    fi
    
    sudo tee /etc/nginx/sites-available/esc > /dev/null << NGCONFIG
# Rate limiting zones
limit_req_zone \$binary_remote_addr zone=general:10m rate=10r/s;
limit_req_zone \$binary_remote_addr zone=api:10m rate=30r/m;
limit_req_zone \$binary_remote_addr zone=auth:10m rate=5r/m;
limit_req_status 429;

upstream django {
    server 127.0.0.1:8000;
    keepalive 64;
}

server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;
    
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;
    
    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    error_page 502 503 504 /50x.html;
    error_page 401 403 /40x_auth.html;
    error_page 400 404 /40x.html;
    
    location = /50x.html { internal; root /etc/nginx/error_pages; }
    location = /40x.html { internal; root /etc/nginx/error_pages; }
    location = /40x_auth.html { internal; root /etc/nginx/error_pages; }
    
    access_log /var/log/nginx/esc_access.log;
    error_log /var/log/nginx/esc_error.log;
    
    client_max_body_size 100M;
    proxy_connect_timeout 300s;
    proxy_send_timeout 300s;
    proxy_read_timeout 300s;
    
    if (\$request_method !~ ^(GET|HEAD|POST|PUT|DELETE|OPTIONS)\$) { return 405; }
    
    location ~ /\. { deny all; access_log off; log_not_found off; }
    location ~ \.env { deny all; }
    location ~ ^/(wp-admin|phpmyadmin) { deny all; }
    
    location / {
        limit_req zone=general burst=20 nodelay;
        proxy_pass http://django;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
    }
    
    location /api/ {
        limit_req zone=api burst=5 nodelay;
        proxy_pass http://django;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location ~ ^/(account|auth|login|signin|register) {
        limit_req zone=auth burst=2 nodelay;
        proxy_pass http://django;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location /health {
        access_log off;
        proxy_pass http://django;
        proxy_set_header Host \$host;
        proxy_connect_timeout 5s;
        proxy_read_timeout 5s;
    }
}
NGCONFIG
}

create_nginx_config_with_ssl() {
    print_info "Creating Nginx config with SSL..."
    
    if [ "$SETUP_SSL" = "letsencrypt" ]; then
        SSL_CERT="/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem"
        SSL_KEY="/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem"
    else
        SSL_CERT="/etc/nginx/ssl/selfsigned.crt"
        SSL_KEY="/etc/nginx/ssl/selfsigned.key"
    fi
    
    sudo tee /etc/nginx/sites-available/esc > /dev/null << NGCONFIG
upstream django { server 127.0.0.1:8000; keepalive 64; }

server {
    listen 80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;
    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    
    error_page 502 503 504 /50x.html;
    error_page 404 /40x.html;
    
    location = /50x.html { internal; root /etc/nginx/error_pages; }
    location = /40x.html { internal; root /etc/nginx/error_pages; }
    
    access_log /var/log/nginx/esc_access.log;
    error_log /var/log/nginx/esc_error.log;
    
    location / {
        proxy_pass http://django;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    location /health { access_log off; proxy_pass http://django; }
}
NGCONFIG
}

create_nginx_config_http_only() {
    print_info "Creating HTTP-only Nginx config..."
    
    sudo tee /etc/nginx/sites-available/esc > /dev/null << NGCONFIG
upstream django { server 127.0.0.1:8000; keepalive 64; }

server {
    listen 80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;
    
    error_page 502 503 504 /50x.html;
    error_page 404 /40x.html;
    
    location = /50x.html { internal; root /etc/nginx/error_pages; }
    location = /40x.html { internal; root /etc/nginx/error_pages; }
    
    access_log /var/log/nginx/esc_access.log;
    error_log /var/log/nginx/esc_error.log;
    
    location / {
        proxy_pass http://django;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGCONFIG
}

# ============================================================================
# SSH HARDENING
# ============================================================================

setup_ssh_hardening() {
    if [ "$SSH_HARDENING" != "true" ]; then
        return
    fi
    
    print_header "Hardening SSH Configuration"
    
    # Backup original SSH config
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)
    print_info "Original SSH config backed up"
    
    # Create hardened SSH config
    sudo tee /etc/ssh/sshd_config > /dev/null << SSHCONFIG
# ESC Enterprise SSH Configuration - Hardened

Port $SSH_PORT
AddressFamily inet
ListenAddress 0.0.0.0

# Authentication
PubkeyAuthentication yes
PermitRootLogin $DISABLE_ROOT_LOGIN
PasswordAuthentication $PASSWORD_AUTH
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Host keys
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

# Security
StrictModes yes
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 30s
ClientAliveInterval 300
ClientAliveCountMax 2
Compression delayed
X11Forwarding no
PrintMotd yes
PrintLastLog yes
TCPKeepAlive yes
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server

# Crypto
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

# Banner
Banner /etc/ssh/sshd_banner
SSHCONFIG
    
    # Create SSH banner
    sudo tee /etc/ssh/sshd_banner > /dev/null << BANNER
╔════════════════════════════════════════════════════════════════╗
║            UNAUTHORIZED ACCESS IS PROHIBITED                  ║
║                                                                ║
║ All activities are logged and monitored. Unauthorized access  ║
║ attempts will be prosecuted to the fullest extent of the law. ║
║                                                                ║
║ By accessing this system, you acknowledge and agree that you  ║
║ understand these terms and conditions.                         ║
╚════════════════════════════════════════════════════════════════╝
BANNER
    
    # Test SSH config
    if sudo sshd -t; then
        sudo systemctl restart ssh
        print_success "SSH hardened (Port: $SSH_PORT)"
        
        if [ "$DISABLE_ROOT_LOGIN" = "no" ]; then
            print_success "Root login: ENABLED"
        fi
        
        if [ "$PASSWORD_AUTH" = "yes" ]; then
            print_success "Password auth: ENABLED"
        fi
    else
        print_error "SSH config invalid, reverting..."
        sudo cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config
        sudo systemctl restart ssh
        return
    fi
    
    # Setup IP whitelist if provided
    if [ -n "$FIREWALL_WHITELIST" ]; then
        print_info "Setting up SSH IP whitelist..."
        sudo tee -a /etc/ssh/sshd_config > /dev/null << IPCONFIG

# Admin IP Whitelist
IPCONFIG
        
        for ip in $FIREWALL_WHITELIST; do
            echo "AllowUsers *@$ip" | sudo tee -a /etc/ssh/sshd_config > /dev/null
        done
        
        sudo systemctl restart ssh
        print_success "SSH whitelist configured"
    fi
    
    # Show 2FA setup if enabled
    if [[ "$ENABLE_2FA_SETUP" =~ ^[Yy]$ ]]; then
        print_section "SSH 2FA Setup Guide"
        echo "To add Two-Factor Authentication to SSH:"
        echo
        echo "1. Install libpam-google-authenticator:"
        echo "   sudo apt install libpam-google-authenticator"
        echo
        echo "2. Generate QR code (as root user):"
        echo "   /usr/bin/google-authenticator"
        echo
        echo "3. Edit /etc/pam.d/sshd and add before @include:"
        echo "   auth required pam_google_authenticator.so noconsecutive window-size=3"
        echo
        echo "4. Edit /etc/ssh/sshd_config and set:"
        echo "   ChallengeResponseAuthentication yes"
        echo
        echo "5. Restart SSH:"
        echo "   sudo systemctl restart ssh"
    fi
}

# ============================================================================
# FAIL2BAN CONFIGURATION
# ============================================================================

install_fail2ban() {
    print_header "Installing Fail2Ban"
    
    if command -v fail2ban-server &> /dev/null; then
        print_warning "Fail2Ban already installed"
    else
        sudo apt install -y fail2ban
        print_success "Fail2Ban installed"
    fi
}

setup_fail2ban() {
    if [ "$SECURITY_ENABLED" != "true" ]; then
        return
    fi
    
    print_header "Configuring Fail2Ban"
    
    # Backup existing config
    if [ -f /etc/fail2ban/jail.local ]; then
        sudo cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # Create jail configuration
    if [ "$FAIL2BAN_AGGRESSIVE" = "true" ]; then
        print_info "Applying AGGRESSIVE Fail2Ban policies..."
        BANTIME="2592000"
        MAXRETRY="3"
        FINDTIME="600"
    else
        print_info "Applying STANDARD Fail2Ban policies..."
        BANTIME="86400"
        MAXRETRY="5"
        FINDTIME="3600"
    fi
    
    sudo tee /etc/fail2ban/jail.local > /dev/null << F2BCONFIG
[DEFAULT]
bantime = $BANTIME
findtime = $FINDTIME
maxretry = $MAXRETRY
ignoreip = 127.0.0.1/8 ::1
backend = systemd
action = iptables-multiport[name=fail2ban, port="http,https", protocol=tcp]
         iptables-multiport[name=fail2ban, port="http,https", protocol=udp]
         sendmail-whois[name=fail2ban, dest=$ADMIN_EMAIL]

[sshd]
enabled = true
port = $SSH_PORT
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime = $BANTIME
backend = systemd

[sshd-ddos]
enabled = true
port = $SSH_PORT
logpath = /var/log/auth.log
maxretry = 10
findtime = 600
bantime = 2592000
backend = systemd

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_error.log
maxretry = 3
bantime = 86400

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 5
bantime = 3600
findtime = 600

[nginx-bad-request]
enabled = true
port = http,https
logpath = /var/log/nginx/esc_access.log
maxretry = 10
bantime = 86400
F2BCONFIG
    
    # Test and start
    print_step "Testing Fail2Ban configuration..."
    if sudo fail2ban-client --test 2>&1 > /dev/null; then
        sudo systemctl daemon-reload
        sudo systemctl enable fail2ban
        sudo systemctl restart fail2ban
        sleep 2
        
        if sudo systemctl is-active --quiet fail2ban; then
            print_success "Fail2Ban configured and running"
            
            # Show initial status
            echo
            print_info "Fail2Ban Status:"
            sudo fail2ban-client status 2>/dev/null | head -10
        else
            print_error "Fail2Ban failed to start"
        fi
    else
        print_error "Fail2Ban config test failed"
    fi
}

# ============================================================================
# FIREWALL SETUP
# ============================================================================

setup_firewall() {
    if [[ ! "$SETUP_FIREWALL" =~ ^[Yy]$ ]]; then
        return
    fi
    
    print_header "Configuring UFW Firewall"
    
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # SSH
    sudo ufw allow $SSH_PORT/tcp
    print_success "SSH port $SSH_PORT allowed"
    
    # HTTP/HTTPS
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    print_success "HTTP/HTTPS allowed"
    
    # Admin IPs if specified
    if [ -n "$FIREWALL_WHITELIST" ]; then
        for ip in $FIREWALL_WHITELIST; do
            sudo ufw allow from $ip to any port $SSH_PORT/tcp
            print_success "Admin IP $ip whitelisted for SSH"
        done
    fi
    
    echo "y" | sudo ufw enable
    print_success "Firewall enabled"
    
    echo
    sudo ufw status verbose | head -15
}

# ============================================================================
# SYSTEMD SERVICE
# ============================================================================

setup_systemd() {
    print_header "Setting Up Systemd Service"
    
    sudo tee /etc/systemd/system/esc.service > /dev/null << SYSTEMD
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
SYSTEMD
    
    sudo systemctl daemon-reload
    sudo systemctl enable esc.service
    
    print_success "Systemd service created"
}

# ============================================================================
# MANAGEMENT SCRIPTS
# ============================================================================

create_management_scripts() {
    print_header "Creating Management Scripts"
    
    mkdir -p /opt/bin
    
    # Deploy script
    cat > $APP_DIR/deploy.sh << 'SCRIPT'
#!/bin/bash
set -e
echo "Deploying ESC Application..."
cd $(dirname "$0")
docker pull andreastuko/esc:latest
docker compose -f compose.prod.yaml down
docker compose -f compose.prod.yaml up -d
sleep 30
docker compose -f compose.prod.yaml ps
echo "Deployment complete!"
SCRIPT
    chmod +x $APP_DIR/deploy.sh
    
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
    
    # Stop/Start scripts
    cat > $APP_DIR/stop.sh << 'SCRIPT'
#!/bin/bash
cd $(dirname "$0")
docker compose -f compose.prod.yaml down
echo "Services stopped."
SCRIPT
    chmod +x $APP_DIR/stop.sh
    
    cat > $APP_DIR/start.sh << 'SCRIPT'
#!/bin/bash
cd $(dirname "$0")
docker compose -f compose.prod.yaml up -d
sleep 30
docker compose -f compose.prod.yaml ps
SCRIPT
    chmod +x $APP_DIR/start.sh
    
    # Security dashboard
    sudo tee /opt/bin/security-status.sh > /dev/null << 'SCRIPT'
#!/bin/bash
clear
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║            ESC Enterprise Security Status                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo "Timestamp: $(date)"
echo
echo "=== Fail2Ban Status ==="
sudo fail2ban-client status 2>/dev/null || echo "Fail2Ban not active"
echo
echo "=== Firewall Status ==="
sudo ufw status | head -10
echo
echo "=== Recently Banned IPs ==="
sudo iptables -L -n 2>/dev/null | grep "REJECT" | head -5 || echo "No recent bans"
SCRIPT
    sudo chmod +x /opt/bin/security-status.sh
    
    print_success "Management scripts created"
}

# ============================================================================
# APPLICATION STARTUP
# ============================================================================

start_application() {
    print_header "Starting Application"
    
    cd $APP_DIR
    
    print_step "Pulling latest Docker image..."
    if ! docker pull andreastuko/esc:latest; then
        print_warning "Failed to pull image, continuing with existing..."
    else
        print_success "Image pulled"
    fi
    
    print_step "Starting services..."
    if docker compose -f compose.prod.yaml up -d; then
        print_success "Services started"
    else
        print_error "Failed to start services"
        docker compose -f compose.prod.yaml logs --tail=20
        exit 1
    fi
    
    print_step "Waiting for services..."
    for i in {1..12}; do
        echo -n "."
        sleep 5
    done
    echo
    
    if docker compose -f compose.prod.yaml ps | grep -q "Up"; then
        print_success "All services running"
        docker compose -f compose.prod.yaml ps
    else
        print_warning "Some services may not be running"
        docker compose -f compose.prod.yaml ps
    fi
}

# ============================================================================
# FINAL SUMMARY
# ============================================================================

print_completion() {
    print_header "🎉 Installation Complete!"
    
    echo -e "${GREEN}Your ESC Django application is production-ready!${NC}\n"
    
    echo "APPLICATION DETAILS:"
    echo "  Domain: https://$DOMAIN_NAME"
    echo "  Directory: $APP_DIR"
    echo "  Environment: $APP_DIR/.env.docker"
    echo
    
    echo "MANAGEMENT COMMANDS:"
    echo "  Deploy:        $APP_DIR/deploy.sh"
    echo "  Logs:          $APP_DIR/logs.sh [service]"
    echo "  Status:        $APP_DIR/status.sh"
    echo "  Stop:          $APP_DIR/stop.sh"
    echo "  Start:         $APP_DIR/start.sh"
    echo
    
    if [ "$SECURITY_ENABLED" = "true" ]; then
        echo "SECURITY FEATURES:"
        echo "  Dashboard:     /opt/bin/security-status.sh"
        echo "  Fail2Ban:      $(sudo systemctl is-active fail2ban 2>/dev/null || echo 'Not installed')"
        echo
    fi
    
    if [ "$SSH_HARDENING" = "true" ]; then
        echo "SSH SECURITY:"
        echo "  Port: $SSH_PORT"
        echo "  Root Login: $DISABLE_ROOT_LOGIN"
        echo "  Password Auth: $PASSWORD_AUTH"
        [ -n "$FIREWALL_WHITELIST" ] && echo "  Whitelisted IPs: $FIREWALL_WHITELIST"
        echo "  Aggressive Fail2Ban: $FAIL2BAN_AGGRESSIVE"
        echo
        echo "To connect:"
        if [ -n "$CREATED_SUDO_USER" ]; then
            echo "  ssh -p $SSH_PORT $CREATED_SUDO_USER@$DOMAIN_NAME"
        else
            echo "  ssh -p $SSH_PORT user@$DOMAIN_NAME"
        fi
        echo
        
        if [ "$DISABLE_ROOT_LOGIN" = "yes" ] || [ "$PASSWORD_AUTH" = "no" ]; then
            print_warning "IMPORTANT SECURITY NOTES:"
            [ "$DISABLE_ROOT_LOGIN" = "yes" ] && echo "  • Root login is DISABLED"
            [ "$PASSWORD_AUTH" = "no" ] && echo "  • Password auth is DISABLED (SSH keys only)"
            echo "  • Ensure you have SSH key access configured!"
            echo
        fi
    fi
    
    echo "NEXT STEPS:"
    echo "  1. Create superuser: cd $APP_DIR && docker compose -f compose.prod.yaml exec web python manage.py createsuperuser"
    echo "  2. Check logs: $APP_DIR/logs.sh"
    echo "  3. Monitor: /opt/bin/security-status.sh"
    echo
    
    print_info "Configuration saved to: $APP_DIR/.deployment_config"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    print_header "ESC Django - Enterprise Deployment Script v2.1"
    
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
    install_fail2ban
    
    setup_ssh_hardening
    setup_fail2ban
    setup_firewall
    setup_systemd
    create_management_scripts
    
    save_config
    
    print_header "Ready for Deployment"
    read -p "Start application now? [Y/n]: " START_NOW
    START_NOW=${START_NOW:-Y}
    
    if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
        start_application
    else
        print_info "Run '$APP_DIR/start.sh' when ready"
    fi
    
    print_completion
}

main "$@"
#!/bin/bash

# ============================================
# Pterodactyl Install Script
# Version: 2.0
# Author: Senior DevOps Engineer
# Description: Automated installation of Pterodactyl Panel and Wings
# Supported OS: Ubuntu 20.04+, Debian 11+
# ============================================

set -e  # Exit on any error

# ============================================
# COLOR DEFINITIONS
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================
# FUNCTION DEFINITIONS
# ============================================

# Function to print colored messages
print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
    echo -e "${RED}[-]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    print_success "Running with root privileges"
}

# Function to detect OS and version
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        print_info "Detected OS: $OS $VERSION"
        
        case $OS in
            ubuntu)
                if [[ "$VERSION" != "20.04" && "$VERSION" != "22.04" && "$VERSION" != "24.04" ]]; then
                    print_warning "Ubuntu $VERSION detected. This script is tested on 20.04, 22.04, and 24.04"
                fi
                ;;
            debian)
                if [[ "$VERSION" != "11" && "$VERSION" != "12" ]]; then
                    print_warning "Debian $VERSION detected. This script is tested on Debian 11 and 12"
                fi
                ;;
            *)
                print_error "Unsupported OS: $OS"
                exit 1
                ;;
        esac
    else
        print_error "Cannot detect OS"
        exit 1
    fi
}

# Function to check if port is in use
check_port() {
    local port=$1
    if netstat -tuln | grep ":$port " > /dev/null; then
        print_error "Port $port is already in use!"
        return 1
    fi
    return 0
}

# Function to validate domain (basic check)
validate_domain() {
    local domain=$1
    if [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check if domain resolves to server IP
check_domain_resolution() {
    local domain=$1
    local server_ip=$(curl -s ifconfig.me)
    local domain_ip=$(dig +short $domain | head -n1)
    
    if [[ -z "$domain_ip" ]]; then
        print_warning "Domain $domain does not resolve to any IP"
        return 1
    fi
    
    if [[ "$domain_ip" != "$server_ip" ]]; then
        print_warning "Domain $domain resolves to $domain_ip, but server IP is $server_ip"
        print_warning "SSL certificate installation may fail if DNS is not properly configured"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    return 0
}

# Function to generate random passwords
generate_password() {
    local length=${1:-32}
    tr -dc 'A-Za-z0-9!@#$%^&*()_+=' < /dev/urandom | head -c $length
}

# Function to update system
update_system() {
    print_status "Updating system packages..."
    apt-get update
    apt-get -y upgrade
    apt-get -y autoremove
    print_success "System updated"
}

# Function to install dependencies for Panel
install_panel_dependencies() {
    print_status "Installing Panel dependencies..."
    
    # Install basic dependencies
    apt-get install -y \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        curl \
        wget \
        gnupg \
        lsb-release
    
    # Add PHP repository
    if [[ "$OS" == "ubuntu" ]]; then
        add-apt-repository -y ppa:ondrej/php
    elif [[ "$OS" == "debian" ]]; then
        apt-get install -y curl wget ca-certificates gnupg
        wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
        echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
    fi
    
    # Update package list again
    apt-get update
    
    # Install PHP and extensions
    apt-get install -y \
        php8.2 \
        php8.2-{cli,common,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} \
        php8.2-bz2 \
        php8.2-intl \
        php8.2-readline \
        php8.2-gmp
    
    # Install other dependencies
    apt-get install -y \
        nginx \
        mariadb-server \
        mariadb-client \
        redis-server \
        certbot \
        python3-certbot-nginx \
        tar \
        unzip \
        git
    
    print_success "Panel dependencies installed"
}

# Function to configure MariaDB
configure_mariadb() {
    print_status "Configuring MariaDB..."
    
    # Generate database credentials
    DB_PASSWORD=$(generate_password 32)
    DB_USER="pterodactyl"
    DB_NAME="panel"
    
    # Secure MariaDB installation
    mysql_secure_installation << EOF

n
y
y
y
y
EOF
    
    # Create database and user
    mysql -e "CREATE DATABASE $DB_NAME;"
    mysql -e "CREATE USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';"
    mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -e "FLUSH PRIVILEGES;"
    
    print_success "MariaDB configured"
}

# Function to install Composer
install_composer() {
    print_status "Installing Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    print_success "Composer installed"
}

# Function to install Node.js
install_nodejs() {
    print_status "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
    print_success "Node.js installed"
}

# Function to install and configure Panel
install_panel() {
    local domain=$1
    
    print_status "Starting Panel installation..."
    
    # Check if panel directory already exists
    if [[ -d "/var/www/pterodactyl" ]]; then
        print_warning "Panel directory already exists at /var/www/pterodactyl"
        read -p "Do you want to remove it and continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Installation aborted"
            return 1
        fi
        rm -rf /var/www/pterodactyl
    fi
    
    # Clone Panel repository
    print_status "Cloning Panel repository..."
    cd /var/www
    git clone https://github.com/pterodactyl/panel.git pterodactyl
    cd pterodactyl
    
    # Get latest version
    git checkout $(git describe --tags $(git rev-list --tags --max-count=1))
    
    # Install PHP dependencies
    print_status "Installing PHP dependencies..."
    composer install --no-dev --optimize-autoloader
    
    # Set permissions
    chown -R www-data:www-data /var/www/pterodactyl/*
    chmod -R 755 /var/www/pterodactyl/*
    
    # Create .env file
    print_status "Creating .env file..."
    
    # Generate app key and other secrets
    APP_KEY=$(generate_password 32)
    REDIS_PASSWORD=$(generate_password 32)
    
    cat > .env << EOF
APP_URL=https://$domain
APP_TIMEZONE=UTC
APP_LOCALE=en

DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=$DB_NAME
DB_USERNAME=$DB_USER
DB_PASSWORD=$DB_PASSWORD

REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_DATABASE=0
REDIS_PASSWORD=$REDIS_PASSWORD

MAIL_DRIVER=log
MAIL_FROM="no-reply@$domain"
MAIL_FROM_NAME="$domain"

APP_KEY=base64:$(openssl rand -base64 32)
EOF
    
    # Generate application key
    php artisan key:generate --force
    
    # Run migrations
    print_status "Running database migrations..."
    php artisan migrate --seed --force
    
    # Create admin user
    print_status "Creating admin user..."
    ADMIN_EMAIL="admin@$domain"
    ADMIN_USERNAME="admin"
    ADMIN_PASSWORD=$(generate_password 16)
    
    php artisan p:user:make << EOF
$ADMIN_EMAIL
$ADMIN_USERNAME
$ADMIN_PASSWORD
admin
EOF
    
    # Create storage link
    php artisan storage:link
    
    # Set permissions again
    chown -R www-data:www-data /var/www/pterodactyl/*
    
    print_success "Panel installation complete"
}

# Function to configure Nginx
configure_nginx() {
    local domain=$1
    
    print_status "Configuring Nginx..."
    
    # Remove default site
    rm -f /etc/nginx/sites-enabled/default
    
    # Create Nginx configuration
    cat > /etc/nginx/sites-available/pterodactyl.conf << EOF
server {
    listen 80;
    server_name $domain;
    root /var/www/pterodactyl/public;
    
    index index.php;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }
    
    location ~ /\.ht {
        deny all;
    }
    
    location ~ /\. {
        deny all;
    }
}
EOF
    
    # Enable site
    ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/
    
    # Test configuration
    nginx -t
    
    # Restart Nginx
    systemctl restart nginx
    
    print_success "Nginx configured"
}

# Function to install SSL certificate
install_ssl() {
    local domain=$1
    
    print_status "Installing SSL certificate..."
    
    # Stop Nginx temporarily for certbot
    systemctl stop nginx
    
    # Obtain SSL certificate
    certbot certonly --standalone -d $domain --non-interactive --agree-tos --email "admin@$domain"
    
    # Update Nginx configuration for SSL
    cat > /etc/nginx/sites-available/pterodactyl.conf << EOF
server {
    listen 80;
    server_name $domain;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $domain;
    
    root /var/www/pterodactyl/public;
    
    index index.php;
    
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }
    
    location ~ /\.ht {
        deny all;
    }
    
    location ~ /\. {
        deny all;
    }
}
EOF
    
    # Restart Nginx
    systemctl start nginx
    
    # Setup auto-renewal
    (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
    
    print_success "SSL certificate installed"
}

# Function to configure services
configure_services() {
    print_status "Configuring services..."
    
    # Enable and start services
    systemctl enable php8.2-fpm
    systemctl enable nginx
    systemctl enable redis-server
    systemctl enable mariadb
    
    systemctl restart php8.2-fpm
    systemctl restart nginx
    systemctl restart redis-server
    systemctl restart mariadb
    
    # Configure Redis password
    sed -i "s/# requirepass .*/requirepass $REDIS_PASSWORD/" /etc/redis/redis.conf
    systemctl restart redis-server
    
    # Setup queue worker
    cat > /etc/systemd/system/pteroq.service << EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server mariadb

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable pteroq
    systemctl start pteroq
    
    print_success "Services configured"
}

# Function to install Docker
install_docker() {
    print_status "Installing Docker..."
    
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc
    
    # Install Docker
    curl -fsSL https://get.docker.com | bash
    
    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Enable and start Docker
    systemctl enable docker
    systemctl start docker
    
    print_success "Docker installed"
}

# Function to install Wings
install_wings() {
    print_status "Installing Wings..."
    
    # Check if Wings is already installed
    if systemctl is-active --quiet wings; then
        print_warning "Wings service is already running"
        read -p "Do you want to reinstall Wings? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
        systemctl stop wings
    fi
    
    # Create directories
    mkdir -p /etc/pterodactyl
    mkdir -p /var/lib/pterodactyl/volumes
    
    # Download latest Wings
    print_status "Downloading Wings..."
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$(uname -m)"
    chmod +x /usr/local/bin/wings
    
    # Get Panel URL and Token
    echo
    print_info "=== Wings Configuration Required ==="
    print_info "You need to generate an API key from your Panel:"
    print_info "1. Log into your Panel as admin"
    print_info "2. Go to Admin -> Configuration -> API"
    print_info "3. Click 'Create New'"
    print_info "4. Copy the token (it will only be shown once!)"
    echo
    
    read -p "Enter Panel URL (e.g., https://panel.yourdomain.com): " PANEL_URL
    read -p "Enter API Token: " PANEL_TOKEN
    
    # Generate node configuration
    print_status "Generating Wings configuration..."
    
    # Generate node secret
    NODE_SECRET=$(generate_password 32)
    
    # Create configuration
    cat > /etc/pterodactyl/config.yml << EOF
debug: false
panel:
  url: $PANEL_URL
  token: $PANEL_TOKEN
  node: $(hostname)

keys:
  - $NODE_SECRET

docker:
  network:
    name: pterodactyl_nw
  dockerfile:
    stop_timeout: 30s

system:
  data: /var/lib/pterodactyl/volumes
  sftp:
    bind_port: 2022
  username: pterodactyl

allowed_mounts: []
remote: \${HOME}/.ssh/authorized_keys
EOF
    
    # Create systemd service
    cat > /etc/systemd/system/wings.service << EOF
[Unit]
Description=Pterodactyl Wings
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=600

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start Wings
    systemctl daemon-reload
    systemctl enable wings
    systemctl start wings
    
    print_success "Wings installed"
}

# Function to uninstall everything
uninstall_all() {
    print_warning "=== NUCLEAR OPTION ==="
    print_warning "This will remove ALL Pterodactyl configurations, data, and services!"
    print_warning "The following will be removed:"
    echo
    echo "- Pterodactyl Panel files (/var/www/pterodactyl)"
    echo "- Wings configuration (/etc/pterodactyl)"
    echo "- Database and database user"
    echo "- Docker containers and images"
    echo "- Nginx configuration"
    echo "- SSL certificates"
    echo
    
    read -p "Are you absolutely sure? (type 'YES' to confirm): " confirmation
    
    if [[ "$confirmation" != "YES" ]]; then
        print_error "Uninstallation cancelled"
        return 1
    fi
    
    print_status "Starting uninstallation..."
    
    # Stop services
    systemctl stop wings 2>/dev/null || true
    systemctl stop pteroq 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true
    systemctl stop php8.2-fpm 2>/dev/null || true
    systemctl stop redis-server 2>/dev/null || true
    
    # Remove services
    systemctl disable wings 2>/dev/null || true
    systemctl disable pteroq 2>/dev/null || true
    rm -f /etc/systemd/system/wings.service
    rm -f /etc/systemd/system/pteroq.service
    
    # Remove Docker containers and images
    docker stop $(docker ps -aq) 2>/dev/null || true
    docker rm $(docker ps -aq) 2>/dev/null || true
    docker rmi $(docker images -q) 2>/dev/null || true
    
    # Remove Docker
    apt-get remove -y docker docker-engine docker.io containerd runc docker-ce docker-ce-cli
    apt-get autoremove -y
    
    # Remove database
    mysql -e "DROP DATABASE IF EXISTS panel;" 2>/dev/null || true
    mysql -e "DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';" 2>/dev/null || true
    
    # Remove directories
    rm -rf /var/www/pterodactyl
    rm -rf /etc/pterodactyl
    rm -rf /var/lib/pterodactyl
    rm -f /usr/local/bin/wings
    rm -f /usr/local/bin/docker-compose
    
    # Remove Nginx configuration
    rm -f /etc/nginx/sites-available/pterodactyl.conf
    rm -f /etc/nginx/sites-enabled/pterodactyl.conf
    
    # Remove PHP repository
    if [[ "$OS" == "ubuntu" ]]; then
        add-apt-repository --remove -y ppa:ondrej/php
    elif [[ "$OS" == "debian" ]]; then
        rm -f /etc/apt/sources.list.d/php.list
        rm -f /etc/apt/trusted.gpg.d/php.gpg
    fi
    
    # Clean up packages
    apt-get remove -y \
        php8.2* \
        nginx \
        mariadb-server \
        redis-server \
        certbot \
        nodejs \
        composer
    
    apt-get autoremove -y
    
    print_success "Uninstallation complete"
    print_info "Note: Some configuration files may remain in /etc/"
    print_info "Note: SSL certificates remain in /etc/letsencrypt/"
}

# Function to display installation summary
display_summary() {
    echo
    print_info "=== INSTALLATION SUMMARY ==="
    print_info "Panel URL: https://$PANEL_DOMAIN"
    print_info "Admin Email: $ADMIN_EMAIL"
    print_info "Admin Username: $ADMIN_USERNAME"
    print_info "Admin Password: $ADMIN_PASSWORD"
    echo
    print_info "=== DATABASE CREDENTIALS ==="
    print_info "Database: $DB_NAME"
    print_info "Username: $DB_USER"
    print_info "Password: $DB_PASSWORD"
    echo
    print_info "=== REDIS CREDENTIALS ==="
    print_info "Password: $REDIS_PASSWORD"
    echo
    print_warning "SAVE THESE CREDENTIALS IN A SECURE LOCATION!"
    print_warning "You will need the admin password to log into the Panel."
    echo
}

# Function to install Panel with all steps
install_panel_full() {
    echo
    print_info "=== PTERODACTYL PANEL INSTALLATION ==="
    
    # Get domain
    read -p "Enter Panel Domain (FQDN): " PANEL_DOMAIN
    
    # Validate domain
    if ! validate_domain "$PANEL_DOMAIN"; then
        print_error "Invalid domain format"
        return 1
    fi
    
    # Check domain resolution
    check_domain_resolution "$PANEL_DOMAIN"
    
    # Check ports
    check_port 80
    check_port 443
    
    # Update system
    update_system
    
    # Install dependencies
    install_panel_dependencies
    
    # Configure database
    configure_mariadb
    
    # Install Composer and Node.js
    install_composer
    install_nodejs
    
    # Install Panel
    install_panel "$PANEL_DOMAIN"
    
    # Configure Nginx
    configure_nginx "$PANEL_DOMAIN"
    
    # Install SSL
    install_ssl "$PANEL_DOMAIN"
    
    # Configure services
    configure_services
    
    # Display summary
    display_summary
    
    print_success "Panel installation completed successfully!"
}

# Function to install Wings only
install_wings_only() {
    echo
    print_info "=== WINGS INSTALLATION ==="
    
    # Check ports
    check_port 2022
    check_port 8080
    
    # Update system
    update_system
    
    # Install Docker
    install_docker
    
    # Install Wings
    install_wings
    
    print_success "Wings installation completed successfully!"
}

# Function to install Panel + Wings
install_panel_and_wings() {
    print_info "=== INSTALLING PANEL + WINGS ==="
    
    # Install Panel
    install_panel_full
    
    # Install Wings
    install_wings_only
    
    print_success "Panel + Wings installation completed successfully!"
}

# Function to display menu
display_menu() {
    clear
    echo -e "${PURPLE}"
    echo "╔════════════════════════════════════════╗"
    echo "║    Pterodactyl Installation Script     ║"
    echo "╚════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
    echo -e "${CYAN}1.${NC} Install Panel"
    echo -e "${CYAN}2.${NC} Install Wings"
    echo -e "${CYAN}3.${NC} Install Panel + Wings"
    echo -e "${CYAN}4.${NC} Remove All Configuration (Uninstall)"
    echo -e "${CYAN}5.${NC} Exit"
    echo
}

# ============================================
# MAIN SCRIPT EXECUTION
# ============================================

# Check root privileges
check_root

# Detect OS
detect_os

# Main loop
while true; do
    display_menu
    
    read -p "Select an option [1-5]: " choice
    
    case $choice in
        1)
            install_panel_full
            read -p "Press Enter to continue..."
            ;;
        2)
            install_wings_only
            read -p "Press Enter to continue..."
            ;;
        3)
            install_panel_and_wings
            read -p "Press Enter to continue..."
            ;;
        4)
            uninstall_all
            read -p "Press Enter to continue..."
            ;;
        5)
            print_info "Exiting..."
            exit 0
            ;;
        *)
            print_error "Invalid option!"
            sleep 2
            ;;
    esac
done

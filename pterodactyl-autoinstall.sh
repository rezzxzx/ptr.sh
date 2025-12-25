#!/bin/bash

# ==============================================
# Pterodactyl Panel + Wings Installer Script
# Version: 2.0.0
# Author: Senior Linux SRE/DevOps
# ==============================================

set -Eeuo pipefail
trap 'handle_error $? $LINENO' ERR

# ==============================================
# GLOBAL VARIABLES & CONFIGURATION
# ==============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Installation paths and settings
PANEL_PATH="/var/www/pterodactyl"
PANEL_USER="ryezx"
PANEL_PASSWORD="ryezx"
PANEL_EMAIL="ryezx@gmail.com"
PANEL_FIRSTNAME="ryezx"
PANEL_LASTNAME="ryezx"
PANEL_DB_NAME="panel"
PANEL_DB_USER="pterodactyl"
INSTALLER_CONF="/etc/pterodactyl/installer.conf"
LOG_FILE="/var/log/pterodactyl-installer.log"
WINGS_BINARY="/usr/local/bin/wings"
WINGS_SERVICE="/etc/systemd/system/wings.service"
PANEL_DOMAIN=""
SERVER_IP=""
OS_NAME=""
OS_VERSION=""
OS_CODENAME=""
INSTALLED_COMPONENTS=()

# Port configurations
PANEL_PORTS=("80/tcp" "443/tcp")
WINGS_PORTS=("8080/tcp" "2022/tcp")

# Progress tracking
TOTAL_STEPS=0
CURRENT_STEP=0

# ==============================================
# ERROR HANDLING & LOGGING
# ==============================================

handle_error() {
    local exit_code=$1
    local line_no=$2
    echo -e "${RED}[ERROR] Script failed at line $line_no with exit code $exit_code${NC}" | tee -a "$LOG_FILE"
    echo -e "${YELLOW}Check detailed logs at: $LOG_FILE${NC}"
    echo -e "${YELLOW}For troubleshooting, refer to: https://pterodactyl.io/community/installation-guides/panel/${NC}"
    exit "$exit_code"
}

log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    if [[ "$level" == "INFO" ]]; then
        echo -e "${BLUE}[INFO]${NC} $message"
    elif [[ "$level" == "WARNING" ]]; then
        echo -e "${YELLOW}[WARNING]${NC} $message"
    elif [[ "$level" == "ERROR" ]]; then
        echo -e "${RED}[ERROR]${NC} $message"
    elif [[ "$level" == "SUCCESS" ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} $message"
    fi
}

update_progress() {
    local step_name="$1"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo -e "${BLUE}[${percent}%]${NC} $step_name"
}

# ==============================================
# INITIALIZATION & VALIDATION
# ==============================================

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root${NC}"
        echo -e "Run with: ${BOLD}sudo bash $0${NC}"
        exit 1
    fi
}

detect_os() {
    log_message "INFO" "Detecting operating system..."
    
    if [[ ! -f /etc/os-release ]]; then
        log_message "ERROR" "Cannot detect OS: /etc/os-release not found"
        exit 1
    fi
    
    # shellcheck source=/dev/null
    source /etc/os-release
    
    OS_NAME="$ID"
    OS_VERSION="$VERSION_ID"
    OS_CODENAME="$VERSION_CODENAME"
    
    # Validate supported OS
    local supported=0
    
    case "$OS_NAME" in
        ubuntu)
            if [[ "$OS_VERSION" == "20.04" || "$OS_VERSION" == "22.04" || "$OS_VERSION" == "24.04" ]]; then
                supported=1
            fi
            ;;
        debian)
            if [[ "$OS_VERSION" == "11" || "$OS_VERSION" == "12" ]]; then
                supported=1
            fi
            ;;
    esac
    
    if [[ $supported -eq 0 ]]; then
        log_message "ERROR" "Unsupported OS: $OS_NAME $OS_VERSION"
        echo -e "${YELLOW}Supported versions:${NC}"
        echo "  Ubuntu: 20.04, 22.04, 24.04"
        echo "  Debian: 11, 12"
        exit 1
    fi
    
    log_message "SUCCESS" "Detected OS: $OS_NAME $OS_VERSION ($OS_CODENAME)"
}

validate_domain() {
    local domain="$1"
    
    # Basic domain format validation
    if ! echo "$domain" | grep -Pq '^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'; then
        log_message "ERROR" "Invalid domain format: $domain"
        return 1
    fi
    
    # Get server public IP
    log_message "INFO" "Detecting server public IP..."
    SERVER_IP=$(curl -s -4 --fail --max-time 10 ifconfig.me 2>/dev/null || curl -s -4 --fail --max-time 10 ipinfo.io/ip 2>/dev/null || echo "")
    
    if [[ -z "$SERVER_IP" ]]; then
        log_message "WARNING" "Could not detect public IP. DNS validation skipped."
        return 0
    fi
    
    # Get DNS A record
    log_message "INFO" "Validating DNS A record for $domain..."
    local dns_ip
    dns_ip=$(dig +short A "$domain" 2>/dev/null | head -n1)
    
    if [[ -z "$dns_ip" ]]; then
        log_message "WARNING" "No A record found for $domain"
        echo -e "${YELLOW}Warning: DNS A record not found or not pointing to this server.${NC}"
        echo -e "${YELLOW}Public IP detected: $SERVER_IP${NC}"
        read -rp "Continue anyway? (y/N): " -n1 confirm
        echo
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return 1
        fi
    elif [[ "$dns_ip" != "$SERVER_IP" ]]; then
        log_message "WARNING" "DNS IP mismatch: $dns_ip != $SERVER_IP"
        echo -e "${YELLOW}Warning: DNS A record ($dns_ip) does not match server IP ($SERVER_IP).${NC}"
        echo -e "${YELLOW}SSL certificate issuance may fail.${NC}"
        read -rp "Continue anyway? (y/N): " -n1 confirm
        echo
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return 1
        fi
    else
        log_message "SUCCESS" "DNS validation passed: $domain → $SERVER_IP"
    fi
    
    PANEL_DOMAIN="$domain"
    return 0
}

# ==============================================
# SYSTEM SETUP FUNCTIONS
# ==============================================

setup_system_user() {
    log_message "INFO" "Setting up system user '$PANEL_USER'..."
    
    if id "$PANEL_USER" &>/dev/null; then
        log_message "INFO" "User '$PANEL_USER' already exists"
        # Update password if user exists
        echo "$PANEL_USER:$PANEL_PASSWORD" | chpasswd 2>/dev/null || true
    else
        useradd -m -s /bin/bash "$PANEL_USER" 2>/dev/null || useradd -m -s /bin/bash -G sudo "$PANEL_USER"
        echo "$PANEL_USER:$PANEL_PASSWORD" | chpasswd
    fi
    
    # Store in installer config
    echo "PANEL_USER=$PANEL_USER" >> "$INSTALLER_CONF"
    echo "PANEL_PASSWORD=$PANEL_PASSWORD" >> "$INSTALLER_CONF"
    
    log_message "SUCCESS" "System user configured"
}

setup_firewall() {
    log_message "INFO" "Configuring firewall..."
    
    # Install UFW if not present
    if ! command -v ufw &>/dev/null; then
        apt-get update
        apt-get install -y ufw
        systemctl enable ufw
    fi
    
    # Enable UFW if not active
    if ! ufw status | grep -q "Status: active"; then
        ufw --force enable
    fi
    
    # Allow SSH (detect current port)
    local ssh_port
    ssh_port=$(grep -oP '^Port \K\d+' /etc/ssh/sshd_config 2>/dev/null || echo "22")
    ufw allow "$ssh_port/tcp" comment "SSH"
    
    # Allow panel ports
    for port in "${PANEL_PORTS[@]}"; do
        ufw allow "$port" comment "Pterodactyl Panel"
    done
    
    # Store firewall rules in config
    echo "FIREWALL_ENABLED=1" >> "$INSTALLER_CONF"
    echo "FIREWALL_PORTS=${PANEL_PORTS[*]}" >> "$INSTALLER_CONF"
    
    log_message "SUCCESS" "Firewall configured"
}

setup_php() {
    log_message "INFO" "Installing PHP stack..."
    
    local php_version=""
    
    # Determine PHP version based on OS
    case "$OS_NAME-$OS_VERSION" in
        ubuntu-20.04) php_version="php7.4" ;;
        ubuntu-22.04|debian-11) php_version="php8.1" ;;
        ubuntu-24.04|debian-12) php_version="php8.2" ;;
        *) php_version="php8.1" ;;
    esac
    
    # Install PHP and extensions
    apt-get install -y \
        "$php_version" \
        "$php_version-common" \
        "$php_version-cli" \
        "$php_version-gd" \
        "$php_version-mysql" \
        "$php_version-mbstring" \
        "$php_version-bcmath" \
        "$php_version-xml" \
        "$php_version-fpm" \
        "$php_version-curl" \
        "$php_version-zip" \
        "$php_version-intl"
    
    # Store PHP version in config
    echo "PHP_VERSION=$php_version" >> "$INSTALLER_CONF"
    
    # Verify PHP installation
    if ! command -v php &> /dev/null; then
        log_message "ERROR" "PHP installation failed. Command 'php' not found."
        exit 1
    fi
    
    log_message "SUCCESS" "PHP $php_version installed"
}

setup_database() {
    log_message "INFO" "Setting up MariaDB database..."
    
    # Install MariaDB
    apt-get install -y mariadb-server mariadb-client
    
    # Secure MariaDB installation
    local root_pass
    root_pass=$(openssl rand -base64 32)
    
    mysql -e "DELETE FROM mysql.user WHERE User='';"
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -e "DROP DATABASE IF EXISTS test;"
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';"
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$root_pass';"
    mysql -e "FLUSH PRIVILEGES;"
    
    # Create panel database and user
    local db_pass
    db_pass=$(openssl rand -base64 32)
    
    mysql -u root -p"$root_pass" <<-EOF
        CREATE DATABASE IF NOT EXISTS $PANEL_DB_NAME;
        CREATE USER IF NOT EXISTS '$PANEL_DB_USER'@'127.0.0.1' IDENTIFIED BY '$db_pass';
        GRANT ALL PRIVILEGES ON $PANEL_DB_NAME.* TO '$PANEL_DB_USER'@'127.0.0.1' WITH GRANT OPTION;
        CREATE USER IF NOT EXISTS '$PANEL_DB_USER'@'localhost' IDENTIFIED BY '$db_pass';
        GRANT ALL PRIVILEGES ON $PANEL_DB_NAME.* TO '$PANEL_DB_USER'@'localhost' WITH GRANT OPTION;
        FLUSH PRIVILEGES;
EOF
    
    # Store database credentials securely
    mkdir -p /etc/pterodactyl
    chmod 700 /etc/pterodactyl
    echo "DB_ROOT_PASS='$root_pass'" >> "$INSTALLER_CONF"
    echo "DB_PASS='$db_pass'" >> "$INSTALLER_CONF"
    chmod 600 "$INSTALLER_CONF"
    
    log_message "SUCCESS" "Database configured"
}

setup_ssl() {
    log_message "INFO" "Setting up SSL with Let's Encrypt..."
    
    # Install certbot
    if [[ "$OS_NAME" == "ubuntu" ]]; then
        apt-get install -y certbot python3-certbot-nginx
    elif [[ "$OS_NAME" == "debian" ]]; then
        apt-get install -y certbot python3-certbot
    fi
    
    # Obtain certificate
    if certbot certonly --nginx --non-interactive --agree-tos --email "$PANEL_EMAIL" -d "$PANEL_DOMAIN" --redirect; then
        log_message "SUCCESS" "SSL certificate obtained for $PANEL_DOMAIN"
        echo "SSL_DOMAIN=$PANEL_DOMAIN" >> "$INSTALLER_CONF"
    else
        log_message "WARNING" "SSL certificate issuance failed. Proceeding with self-signed."
        # Generate self-signed certificate as fallback
        mkdir -p /etc/ssl/pterodactyl
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/ssl/pterodactyl/private.key \
            -out /etc/ssl/pterodactyl/certificate.crt \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=$PANEL_DOMAIN"
        echo "SSL_SELF_SIGNED=1" >> "$INSTALLER_CONF"
    fi
}

# ==============================================
# PANEL INSTALLATION
# ==============================================

install_panel_dependencies() {
    log_message "INFO" "Installing panel dependencies..."
    
    # Update package lists with retry
    for i in {1..3}; do
        if apt-get update; then
            break
        fi
        log_message "WARNING" "apt-get update attempt $i failed, retrying..."
        sleep 2
    done
    
    # Install basic tools
    apt-get install -y \
        curl tar unzip git ca-certificates \
        lsb-release gnupg apt-transport-https \
        software-properties-common
    
    # Setup PHP FIRST (before composer)
    setup_php
    
    # Install Node.js LTS
    log_message "INFO" "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y nodejs build-essential
    
    # Install Composer with retry logic
    log_message "INFO" "Installing Composer..."
    for i in {1..3}; do
        if curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php; then
            if php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer --quiet; then
                rm -f /tmp/composer-setup.php
                log_message "SUCCESS" "Composer installed successfully"
                break
            fi
        fi
        if [[ $i -lt 3 ]]; then
            log_message "WARNING" "Composer installation attempt $i failed, retrying..."
            sleep 2
        else
            log_message "WARNING" "Failed to install Composer after 3 attempts, trying alternative method..."
            # Try alternative installation method
            php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup-alt.php');"
            php /tmp/composer-setup-alt.php --install-dir=/usr/local/bin --filename=composer
            rm -f /tmp/composer-setup-alt.php
        fi
    done
    
    # Verify composer installation
    if ! command -v composer &> /dev/null; then
        log_message "ERROR" "Composer installation failed completely"
        exit 1
    fi
    
    # Install Redis
    apt-get install -y redis-server
    
    # Setup database
    setup_database
    
    log_message "SUCCESS" "Panel dependencies installed"
}

install_panel() {
    log_message "INFO" "Starting Pterodactyl Panel installation..."
    
    # Get domain if not set
    if [[ -z "$PANEL_DOMAIN" ]]; then
        while true; do
            read -rp "Enter panel domain/FQDN (e.g., panel.example.com): " domain_input
            if validate_domain "$domain_input"; then
                break
            fi
        done
    fi
    
    TOTAL_STEPS=15
    CURRENT_STEP=0
    
    update_progress "Installing dependencies"
    install_panel_dependencies
    
    update_progress "Creating panel directory"
    mkdir -p "$PANEL_PATH"
    chown -R "$PANEL_USER":"$PANEL_USER" "$PANEL_PATH"
    
    update_progress "Downloading panel files"
    cd "$PANEL_PATH"
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
    
    update_progress "Installing PHP dependencies"
    sudo -u "$PANEL_USER" php -d memory_limit=-1 /usr/local/bin/composer install --no-dev --optimize-autoloader --no-interaction
    
    update_progress "Setting up environment"
    cp .env.example .env
    sudo -u "$PANEL_USER" php artisan key:generate --force
    
    # Update .env file with database credentials
    local db_pass
    db_pass=$(grep "DB_PASS=" "$INSTALLER_CONF" | cut -d= -f2 | tr -d "'")
    
    sed -i "s/APP_URL=.*/APP_URL=https:\/\/$PANEL_DOMAIN/" .env
    sed -i "s/DB_DATABASE=.*/DB_DATABASE=$PANEL_DB_NAME/" .env
    sed -i "s/DB_USERNAME=.*/DB_USERNAME=$PANEL_DB_USER/" .env
    sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$db_pass/" .env
    sed -i "s/APP_TIMEZONE=.*/APP_TIMEZONE=Asia\/Jakarta/" .env
    
    update_progress "Running database migrations"
    sudo -u "$PANEL_USER" php artisan migrate --seed --force
    
    update_progress "Setting up queue worker"
    cat > /etc/systemd/system/pteroq.service << EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=$PANEL_USER
Group=$PANEL_USER
Restart=always
ExecStart=/usr/bin/php $PANEL_PATH/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable --now pteroq.service
    
    update_progress "Building frontend assets"
    sudo -u "$PANEL_USER" npm ci --only=production
    sudo -u "$PANEL_USER" npm run build
    
    update_progress "Setting permissions"
    chown -R "$PANEL_USER":www-data "$PANEL_PATH"
    chmod -R 755 "$PANEL_PATH"
    
    update_progress "Configuring nginx"
    apt-get install -y nginx
    
    cat > /etc/nginx/sites-available/pterodactyl.conf << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $PANEL_DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $PANEL_DOMAIN;
    
    root $PANEL_PATH/public;
    index index.php;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$PANEL_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$PANEL_DOMAIN/privkey.pem;
    
    # Self-signed fallback
    ssl_certificate /etc/ssl/pterodactyl/certificate.crt;
    ssl_certificate_key /etc/ssl/pterodactyl/private.key;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php$(php -r "echo PHP_MAJOR_VERSION.PHP_MINOR_VERSION;")-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size = 100M";
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
}
EOF
    
    ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx
    
    update_progress "Setting up SSL"
    setup_ssl
    
    update_progress "Creating admin user"
    # Check if user already exists
    if ! sudo -u "$PANEL_USER" php artisan p:user:list | grep -q "$PANEL_EMAIL"; then
        expect <<EOF
spawn sudo -u $PANEL_USER php artisan p:user:make
expect "Email address:*"
send "$PANEL_EMAIL\r"
expect "Username:*"
send "$PANEL_USER\r"
expect "First name:*"
send "$PANEL_FIRSTNAME\r"
expect "Last name:*"
send "$PANEL_LASTNAME\r"
expect "Password:*"
send "$PANEL_PASSWORD\r"
expect "Confirm password:*"
send "$PANEL_PASSWORD\r"
expect eof
EOF
    else
        log_message "INFO" "Admin user already exists"
    fi
    
    update_progress "Setting up firewall"
    setup_firewall
    
    # Mark panel as installed
    INSTALLED_COMPONENTS+=("panel")
    echo "PANEL_INSTALLED=1" >> "$INSTALLER_CONF"
    echo "PANEL_DOMAIN=$PANEL_DOMAIN" >> "$INSTALLER_CONF"
    
    log_message "SUCCESS" "Pterodactyl Panel installation completed!"
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN} PANEL INSTALLATION COMPLETE${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "URL: ${BOLD}https://$PANEL_DOMAIN${NC}"
    echo -e "Admin Username: ${BOLD}$PANEL_USER${NC}"
    echo -e "Admin Password: ${BOLD}$PANEL_PASSWORD${NC}"
    echo -e "Admin Email: ${BOLD}$PANEL_EMAIL${NC}"
    echo -e "Log file: ${BOLD}$LOG_FILE${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# ==============================================
# WINGS INSTALLATION
# ==============================================

install_docker() {
    log_message "INFO" "Installing Docker..."
    
    # Remove old Docker versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Install dependencies
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$OS_NAME/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS_NAME $OS_CODENAME stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start and enable Docker
    systemctl enable --now docker
    
    # Add panel user to docker group
    usermod -aG docker "$PANEL_USER"
    
    echo "DOCKER_INSTALLED=1" >> "$INSTALLER_CONF"
    log_message "SUCCESS" "Docker installed"
}

install_wings() {
    log_message "INFO" "Starting Wings installation..."
    
    TOTAL_STEPS=8
    CURRENT_STEP=0
    
    update_progress "Installing Docker"
    install_docker
    
    update_progress "Downloading Wings binary"
    mkdir -p /etc/pterodactyl
    curl -L -o "$WINGS_BINARY" https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
    chmod +x "$WINGS_BINARY"
    
    update_progress "Creating Wings configuration"
    mkdir -p /etc/pterodactyl /var/lib/pterodactyl /var/log/pterodactyl
    
    cat > /etc/pterodactyl/config.yml << EOF
debug: false
panel:
  host: https://localhost
  token: ""
  trust: ""
client:
  trusted_proxies: []
  remote: ""
  token:
    user: ""
    server: ""
api:
  host: 0.0.0.0
  port: 8080
  ssl:
    enabled: false
    certificate: ""
    key: ""
system:
  data: /var/lib/pterodactyl
  log_directory: /var/log/pterodactyl
  username: pterodactyl
  timezone: Asia/Jakarta
docker:
  network:
    name: pterodactyl_nw
    interface: ""
  size: 0
  engine: ""
  firewall:
    enabled: false
EOF
    
    update_progress "Creating Wings service"
    cat > "$WINGS_SERVICE" << EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=$WINGS_BINARY
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30

[Install]
WantedBy=multi-user.target
EOF
    
    update_progress "Setting up systemd"
    mkdir -p /var/run/wings
    systemctl daemon-reload
    systemctl enable wings
    
    update_progress "Opening firewall ports"
    for port in "${WINGS_PORTS[@]}"; do
        ufw allow "$port" comment "Pterodactyl Wings"
    done
    
    echo "WINGS_PORTS=${WINGS_PORTS[*]}" >> "$INSTALLER_CONF"
    
    update_progress "Creating Wings user"
    if ! id pterodactyl &>/dev/null; then
        useradd --system --no-create-home --shell /sbin/nologin pterodactyl
    fi
    
    chown -R pterodactyl:pterodactyl /var/lib/pterodactyl /var/log/pterodactyl
    
    # Mark wings as installed
    INSTALLED_COMPONENTS+=("wings")
    echo "WINGS_INSTALLED=1" >> "$INSTALLER_CONF"
    
    update_progress "Installation complete"
    
    log_message "SUCCESS" "Wings installation completed!"
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN} WINGS INSTALLATION COMPLETE${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Wings binary: ${BOLD}$WINGS_BINARY${NC}"
    echo -e "Configuration: ${BOLD}/etc/pterodactyl/config.yml${NC}"
    echo -e "Service: ${BOLD}systemctl status wings${NC}"
    echo -e "Ports: ${BOLD}8080 (API), 2022 (SFTP)${NC}"
    echo -e "${YELLOW}Note: You need to generate an API token from the panel${NC}"
    echo -e "${YELLOW}and configure it in /etc/pterodactyl/config.yml${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# ==============================================
# REMOVAL FUNCTIONS
# ==============================================

confirm_removal() {
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}        WARNING: DESTRUCTIVE ACTION${NC}"
    echo -e "${RED}========================================${NC}"
    echo
    echo -e "${YELLOW}This will remove ALL Pterodactyl components:${NC}"
    echo "  • Pterodactyl Panel files and database"
    echo "  • Wings service and configuration"
    echo "  • Nginx configuration for panel"
    echo "  • SSL certificates"
    echo "  • Firewall rules"
    echo "  • Docker (if installed by this script)"
    echo
    echo -e "${RED}This action is irreversible!${NC}"
    echo
    
    read -rp "Type 'YES' to confirm removal: " confirmation
    if [[ "$confirmation" != "YES" ]]; then
        echo -e "${GREEN}Removal cancelled${NC}"
        return 1
    fi
    
    # Double confirmation
    echo
    echo -e "${RED}Are you absolutely sure? This will delete all panel data!${NC}"
    read -rp "Type 'CONFIRM' to proceed: " final_confirmation
    if [[ "$final_confirmation" != "CONFIRM" ]]; then
        echo -e "${GREEN}Removal cancelled${NC}"
        return 1
    fi
    
    return 0
}

remove_all() {
    log_message "WARNING" "Starting complete removal of Pterodactyl"
    
    if ! confirm_removal; then
        return
    fi
    
    log_message "INFO" "Stopping services..."
    
    # Stop and disable services
    systemctl stop wings pteroq 2>/dev/null || true
    systemctl disable wings pteroq 2>/dev/null || true
    
    # Remove panel files
    if [[ -d "$PANEL_PATH" ]]; then
        log_message "INFO" "Removing panel files from $PANEL_PATH"
        rm -rf "$PANEL_PATH"
    fi
    
    # Remove nginx configuration
    if [[ -f "/etc/nginx/sites-enabled/pterodactyl.conf" ]]; then
        rm -f /etc/nginx/sites-enabled/pterodactyl.conf
    fi
    if [[ -f "/etc/nginx/sites-available/pterodactyl.conf" ]]; then
        rm -f /etc/nginx/sites-available/pterodactyl.conf
    fi
    
    # Remove SSL certificates
    if [[ -n "$PANEL_DOMAIN" ]] && [[ -d "/etc/letsencrypt/live/$PANEL_DOMAIN" ]]; then
        certbot delete --cert-name "$PANEL_DOMAIN" --non-interactive || true
    fi
    
    # Remove self-signed certificates
    if [[ -d "/etc/ssl/pterodactyl" ]]; then
        rm -rf /etc/ssl/pterodactyl
    fi
    
    # Remove wings
    if [[ -f "$WINGS_BINARY" ]]; then
        rm -f "$WINGS_BINARY"
    fi
    if [[ -f "$WINGS_SERVICE" ]]; then
        rm -f "$WINGS_SERVICE"
    fi
    systemctl daemon-reload
    
    # Remove data directories
    rm -rf /var/lib/pterodactyl /var/log/pterodactyl /etc/pterodactyl
    
    # Remove firewall rules
    if command -v ufw &>/dev/null; then
        for port in "${PANEL_PORTS[@]}" "${WINGS_PORTS[@]}"; do
            ufw delete allow "$port" 2>/dev/null || true
        done
    fi
    
    # Remove Docker (only if we installed it)
    if grep -q "DOCKER_INSTALLED=1" "$INSTALLER_CONF" 2>/dev/null; then
        apt-get remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        rm -rf /var/lib/docker /etc/docker
        groupdel docker 2>/dev/null || true
    fi
    
    # Remove database
    if [[ -f "$INSTALLER_CONF" ]]; then
        local root_pass
        root_pass=$(grep "DB_ROOT_PASS=" "$INSTALLER_CONF" | cut -d= -f2 | tr -d "'")
        mysql -u root -p"$root_pass" -e "DROP DATABASE IF EXISTS $PANEL_DB_NAME; DROP USER IF EXISTS '$PANEL_DB_USER'@'127.0.0.1'; DROP USER IF EXISTS '$PANEL_DB_USER'@'localhost';" 2>/dev/null || true
    fi
    
    # Remove installer configuration
    rm -f "$INSTALLER_CONF"
    
    # Remove log file
    rm -f "$LOG_FILE"
    
    log_message "SUCCESS" "Complete removal finished"
    echo -e "${GREEN}All Pterodactyl components have been removed${NC}"
}

# ==============================================
# MAIN MENU & EXECUTION
# ==============================================

show_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    Pterodactyl Installer v2.0.0${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BOLD}Detected OS: $OS_NAME $OS_VERSION${NC}"
    echo -e "${BOLD}Server IP: ${SERVER_IP:-Not detected}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    echo -e "   ${GREEN}1.${NC} Install Panel Only"
    echo -e "   ${GREEN}2.${NC} Install Wings Only"
    echo -e "   ${GREEN}3.${NC} Install Panel + Wings"
    echo -e "   ${RED}4.${NC} Remove ALL Configuration"
    echo -e "   ${YELLOW}5.${NC} Exit"
    echo
    echo -e "${BLUE}========================================${NC}"
}

install_both() {
    log_message "INFO" "Installing both Panel and Wings"
    install_panel
    install_wings
}

main() {
    # Create log file
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1
    
    log_message "INFO" "Starting Pterodactyl installer"
    log_message "INFO" "Script started at $(date)"
    
    # Initial setup
    require_root
    detect_os
    
    # Try to get server IP
    SERVER_IP=$(curl -s -4 --fail --max-time 5 ifconfig.me 2>/dev/null || curl -s -4 --fail --max-time 5 ipinfo.io/ip 2>/dev/null || echo "Not detected")
    
    # Load existing configuration if any
    if [[ -f "$INSTALLER_CONF" ]]; then
        log_message "INFO" "Found existing installation configuration"
        # shellcheck source=/dev/null
        source "$INSTALLER_CONF"
        if [[ -n "$PANEL_DOMAIN" ]]; then
            log_message "INFO" "Previous panel domain: $PANEL_DOMAIN"
        fi
    fi
    
    # Main menu loop
    while true; do
        show_menu
        read -rp "Select option [1-5]: " choice
        
        case $choice in
            1)
                echo -e "\n${GREEN}Selected: Install Panel Only${NC}\n"
                install_panel
                ;;
            2)
                echo -e "\n${GREEN}Selected: Install Wings Only${NC}\n"
                install_wings
                ;;
            3)
                echo -e "\n${GREEN}Selected: Install Panel + Wings${NC}\n"
                install_both
                ;;
            4)
                echo -e "\n${RED}Selected: Remove ALL Configuration${NC}\n"
                remove_all
                ;;
            5)
                echo -e "\n${YELLOW}Exiting installer${NC}"
                log_message "INFO" "Installer exited by user"
                exit 0
                ;;
            *)
                echo -e "\n${RED}Invalid option. Please select 1-5${NC}"
                sleep 2
                ;;
        esac
        
        if [[ $choice =~ ^[1-3]$ ]]; then
            echo
            read -rp "Press Enter to return to main menu..."
        fi
    done
}

# ==============================================
# SCRIPT EXECUTION
# ==============================================

# Check if running in terminal
if [[ ! -t 0 ]]; then
    echo "This script must be run in an interactive terminal"
    exit 1
fi

# Run main function
main

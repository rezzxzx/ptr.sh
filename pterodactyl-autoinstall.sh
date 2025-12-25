#!/bin/bash

# ============================================
# Pterodactyl Auto-Installer untuk Ubuntu
# Konfigurasi Otomatis: ryezx@gmail.com / ryezx / ryezx
# ============================================

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variabel konfigurasi OTOMATIS
PANEL_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
WINGS_URL="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64"
BACKUP_DIR="/var/lib/pterodactyl/backups"
LOG_FILE="/var/log/pterodactyl-autoinstall.log"

# KONFIGURASI OTOMATIS - SESUAI PERMINTAAN
AUTO_EMAIL="ryezx@gmail.com"
AUTO_USERNAME="ryezx"
AUTO_PASSWORD="ryezx"
AUTO_ADMIN_NAME="Ryezx Administrator"
AUTO_TIMEZONE="Asia/Jakarta"

# Fungsi untuk logging
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Fungsi untuk menampilkan header
show_header() {
    clear
    echo -e "${BLUE}"
    echo "================================================"
    echo "   Pterodactyl Auto-Installer"
    echo "   User: ryezx / Pass: ryezx"
    echo "================================================"
    echo -e "${NC}"
}

# Fungsi untuk cek root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: Script harus dijalankan sebagai root!${NC}"
        echo -e "Gunakan: ${GREEN}sudo bash $0${NC}"
        exit 1
    fi
}

# Fungsi untuk cek Ubuntu version
check_ubuntu_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        UBUNTU_VERSION=$VERSION_ID
        
        case $UBUNTU_VERSION in
            "20.04"|"22.04"|"24.04")
                log "Ubuntu $UBUNTU_VERSION terdeteksi - OK"
                ;;
            *)
                echo -e "${RED}Error: Ubuntu version $UBUNTU_VERSION tidak didukung!${NC}"
                echo -e "Hanya Ubuntu 20.04, 22.04, dan 24.04 yang didukung."
                exit 1
                ;;
        esac
    else
        echo -e "${RED}Error: Sistem operasi bukan Ubuntu!${NC}"
        exit 1
    fi
}

# Fungsi untuk update sistem
update_system() {
    log "Memperbarui sistem..."
    apt-get update -y >> "$LOG_FILE" 2>&1
    apt-get upgrade -y >> "$LOG_FILE" 2>&1
    apt-get autoremove -y >> "$LOG_FILE" 2>&1
    
    # Install dependensi dasar
    apt-get install -y curl wget git nano htop ufw software-properties-common \
        apt-transport-https ca-certificates gnupg lsb-release >> "$LOG_FILE" 2>&1
    
    log "Sistem berhasil diperbarui"
}

# Fungsi install dependencies
install_dependencies() {
    log "Menginstal dependencies..."
    
    # PHP repository untuk Ubuntu 20.04
    if [[ $UBUNTU_VERSION == "20.04" ]]; then
        add-apt-repository -y ppa:ondrej/php >> "$LOG_FILE" 2>&1
    fi
    
    apt-get update -y >> "$LOG_FILE" 2>&1
    
    # Install PHP dan ekstensi berdasarkan versi Ubuntu
    if [[ $UBUNTU_VERSION == "24.04" ]]; then
        apt-get install -y php8.3 php8.3-{cli,common,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} \
            mariadb-server nginx tar unzip git redis-server >> "$LOG_FILE" 2>&1
        PHP_VERSION="8.3"
        PHP_SERVICE="php8.3-fpm"
    elif [[ $UBUNTU_VERSION == "22.04" ]]; then
        apt-get install -y php8.1 php8.1-{cli,common,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} \
            mariadb-server nginx tar unzip git redis-server >> "$LOG_FILE" 2>&1
        PHP_VERSION="8.1"
        PHP_SERVICE="php8.1-fpm"
    else
        apt-get install -y php8.1 php8.1-{cli,common,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} \
            mariadb-server nginx tar unzip git redis-server >> "$LOG_FILE" 2>&1
        PHP_VERSION="8.1"
        PHP_SERVICE="php8.1-fpm"
    fi
    
    # Install Composer
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer >> "$LOG_FILE" 2>&1
    
    log "Dependencies berhasil diinstal"
}

# Fungsi konfigurasi database
configure_database() {
    log "Mengkonfigurasi database..."
    
    # Start dan enable MySQL
    systemctl start mariadb >> "$LOG_FILE" 2>&1
    systemctl enable mariadb >> "$LOG_FILE" 2>&1
    
    # Buat database dan user
    MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
    PANEL_DB_PASSWORD=$(openssl rand -base64 32)
    
    # Secure installation
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';" >> "$LOG_FILE" 2>&1
    
    # Buat file konfigurasi MySQL
    cat > /root/.my.cnf << EOF
[client]
user=root
password=$MYSQL_ROOT_PASSWORD
EOF
    
    chmod 600 /root/.my.cnf
    
    # Buat database untuk panel
    mysql -e "CREATE DATABASE panel;" >> "$LOG_FILE" 2>&1
    mysql -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$PANEL_DB_PASSWORD';" >> "$LOG_FILE" 2>&1
    mysql -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;" >> "$LOG_FILE" 2>&1
    mysql -e "FLUSH PRIVILEGES;" >> "$LOG_FILE" 2>&1
    
    # Simpan password
    cat > /root/pterodactyl_db_info.txt << EOF
=== INFORMASI DATABASE PTERODACTYL ===
Tanggal: $(date)
Server: $(hostname)

MySQL Root Password: $MYSQL_ROOT_PASSWORD
Panel Database Password: $PANEL_DB_PASSWORD
Database Name: panel
Database User: pterodactyl
Database Host: 127.0.0.1

=== KONFIGURASI ADMIN ===
Email: $AUTO_EMAIL
Username: $AUTO_USERNAME
Password: $AUTO_PASSWORD
====================================
EOF
    
    log "Database berhasil dikonfigurasi"
    echo -e "${GREEN}Password database disimpan di /root/pterodactyl_db_info.txt${NC}"
}

# Fungsi untuk meminta FQDN
get_fqdn() {
    echo -e "${YELLOW}╔════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║   MASUKKAN DOMAIN/FQDN UNTUK PANEL     ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Contoh: ${GREEN}panel.domain-anda.com${NC}"
    echo -e "Atau gunakan IP: ${GREEN}http://$(curl -s ifconfig.me)${NC}"
    echo ""
    
    while true; do
        read -p "Masukkan FQDN atau IP untuk panel: " FQDN
        
        if [[ -n "$FQDN" ]]; then
            # Cek jika user memasukkan http:// atau https://
            if [[ "$FQDN" == http://* ]] || [[ "$FQDN" == https://* ]]; then
                echo -e "${RED}Hanya masukkan domain/IP tanpa http://${NC}"
                continue
            fi
            
            # Konfirmasi
            echo ""
            echo -e "Domain/IP yang dimasukkan: ${GREEN}$FQDN${NC}"
            read -p "Apakah ini benar? (y/n): " confirm
            
            if [[ $confirm =~ ^[Yy]$ ]]; then
                break
            fi
        else
            echo -e "${RED}FQDN tidak boleh kosong!${NC}"
        fi
    done
    
    # Simpan FQDN ke variabel global
    PANEL_FQDN="$FQDN"
    log "FQDN yang dipilih: $PANEL_FQDN"
}

# Fungsi install Pterodactyl Panel
install_panel() {
    log "Menginstal Pterodactyl Panel..."
    
    # Minta FQDN
    get_fqdn
    
    # Buat directory
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    
    log "Mendownload panel dari: $PANEL_URL"
    curl -L $PANEL_URL | tar --strip-components=1 -xzv >> "$LOG_FILE" 2>&1
    
    # Set permissions
    chmod -R 755 storage/* bootstrap/cache/
    chown -R www-data:www-data /var/www/pterodactyl/*
    
    # Install dependencies Composer
    log "Menginstal dependencies Composer..."
    composer install --no-dev --optimize-autoloader >> "$LOG_FILE" 2>&1
    
    # Copy environment file
    cp .env.example .env
    
    # Generate key
    php artisan key:generate --force >> "$LOG_FILE" 2>&1
    
    # Setup environment dengan konfigurasi OTOMATIS
    log "Mengkonfigurasi environment panel..."
    php artisan p:environment:setup \
        --author="$AUTO_EMAIL" \
        --url="http://$PANEL_FQDN" \
        --timezone="$AUTO_TIMEZONE" \
        --cache=redis \
        --session=redis \
        --queue=redis \
        --redis-host=127.0.0.1 \
        --redis-port=6379 \
        --settings-ui=true >> "$LOG_FILE" 2>&1
    
    # Setup database
    php artisan p:environment:database \
        --host=127.0.0.1 \
        --port=3306 \
        --database=panel \
        --username=pterodactyl \
        --password=$PANEL_DB_PASSWORD >> "$LOG_FILE" 2>&1
    
    # Migrasi database
    log "Menjalankan migrasi database..."
    php artisan migrate --seed --force >> "$LOG_FILE" 2>&1
    
    # Buat user admin OTOMATIS dengan konfigurasi yang diminta
    log "Membuat user admin otomatis..."
    php artisan p:user:make \
        --email="$AUTO_EMAIL" \
        --username="$AUTO_USERNAME" \
        --name="$AUTO_ADMIN_NAME" \
        --admin=1 \
        --password="$AUTO_PASSWORD" >> "$LOG_FILE" 2>&1
    
    # Simpan credentials admin
    cat > /root/pterodactyl_admin_credentials.txt << EOF
=== CREDENTIALS ADMIN PTERODACTYL ===
Tanggal: $(date)
Server: $(hostname)
Panel URL: http://$PANEL_FQDN

=== LOGIN DETAILS ===
Email: $AUTO_EMAIL
Username: $AUTO_USERNAME
Password: $AUTO_PASSWORD

=== DATABASE INFO ===
MySQL Root: $MYSQL_ROOT_PASSWORD
Panel DB Pass: $PANEL_DB_PASSWORD

=== CATATAN ===
1. Ganti password setelah login pertama
2. Setup SSL untuk keamanan
3. Backup credentials ini
===============================
EOF
    
    log "Panel berhasil diinstal"
    echo -e "${GREEN}Credentials admin disimpan di /root/pterodactyl_admin_credentials.txt${NC}"
}

# Fungsi konfigurasi Nginx
configure_nginx() {
    log "Mengkonfigurasi Nginx..."
    
    # Hentikan Nginx
    systemctl stop nginx
    
    # Backup konfigurasi default
    mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
    
    # Buat konfigurasi untuk Pterodactyl
    cat > /etc/nginx/sites-available/pterodactyl.conf << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $PANEL_FQDN;
    root /var/www/pterodactyl/public;
    
    index index.html index.htm index.php;
    charset utf-8;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }
    
    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;
    
    # allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;
    
    sendfile off;
    
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/$PHP_SERVICE.sock;
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
        include /etc/nginx/fastcgi_params;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
EOF
    
    # Aktifkan konfigurasi
    ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Test konfigurasi
    if nginx -t >> "$LOG_FILE" 2>&1; then
        log "Konfigurasi Nginx valid"
    else
        echo -e "${RED}Error: Konfigurasi Nginx tidak valid!${NC}"
        exit 1
    fi
    
    # Start Nginx
    systemctl start nginx
    systemctl enable nginx
    systemctl restart $PHP_SERVICE
    
    log "Nginx berhasil dikonfigurasi untuk $PANEL_FQDN"
}

# Fungsi install Wings
install_wings() {
    log "Menginstal Wings..."
    
    # Install Docker
    log "Menginstal Docker..."
    curl -fsSL https://get.docker.com | sh >> "$LOG_FILE" 2>&1
    
    # Install dependencies untuk Wings
    apt-get install -y docker-ce docker-ce-cli containerd.io >> "$LOG_FILE" 2>&1
    
    # Download dan install Wings
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings $WINGS_URL >> "$LOG_FILE" 2>&1
    chmod +x /usr/local/bin/wings
    
    # Generate Wings configuration
    cat > /etc/pterodactyl/config.yml << EOF
debug: false
system:
  data: /var/lib/pterodactyl/containers
  sftp:
    bind_port: 2022
  username: pterodactyl
  timezone: $AUTO_TIMEZONE
docker:
  network:
    name: pterodactyl_nw
    interface: 172.18.0.1
  containers:
    image: ghcr.io/pterodactyl/yolks:latest
    stop_timeout: 10s
  networks: []
allow_cors: false
upload_limit: 100
redis: {}
EOF
    
    # Buat user pterodactyl
    useradd -r -d /var/lib/pterodactyl -s /bin/false pterodactyl
    mkdir -p /var/lib/pterodactyl
    chown -R pterodactyl:pterodactyl /var/lib/pterodactyl
    
    # Buat systemd service untuk Wings
    cat > /etc/systemd/system/wings.service << EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=pterodactyl
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd dan enable service
    systemctl daemon-reload
    systemctl enable --now wings >> "$LOG_FILE" 2>&1
    
    # Buat API key untuk Wings (akan digenerate di panel)
    log "Wings berhasil diinstal"
    echo -e "${YELLOW}Catatan: Anda perlu membuat API key di panel untuk menghubungkan Wings${NC}"
}

# Fungsi konfigurasi firewall
configure_firewall() {
    log "Mengkonfigurasi firewall..."
    
    # Reset firewall
    ufw --force reset >> "$LOG_FILE" 2>&1
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow 22/tcp comment 'SSH'
    
    # Allow HTTP/HTTPS untuk Panel
    ufw allow 80/tcp comment 'HTTP Panel'
    ufw allow 443/tcp comment 'HTTPS Panel'
    
    # Allow ports untuk Wings
    ufw allow 2022/tcp comment 'Wings SFTP'
    ufw allow 8080/tcp comment 'Wings API'
    
    # Allow beberapa port game umum
    ufw allow 25565/tcp comment 'Minecraft'
    ufw allow 25565/udp comment 'Minecraft UDP'
    ufw allow 27015/tcp comment 'CS:GO'
    ufw allow 27015/udp comment 'CS:GO UDP'
    ufw allow 7777/tcp comment 'Ark'
    ufw allow 7777/udp comment 'Ark UDP'
    
    # Enable UFW
    echo "y" | ufw enable >> "$LOG_FILE" 2>&1
    
    # Tampilkan status
    ufw status numbered
    
    log "Firewall berhasil dikonfigurasi"
}

# Fungsi setup cron jobs
setup_cron() {
    log "Menyetup cron jobs..."
    
    # Buat cron job untuk panel
    crontab -l > mycron 2>/dev/null || true
    echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1" >> mycron
    crontab mycron
    rm mycron
    
    # Buat cron job untuk backup otomatis
    mkdir -p /etc/cron.daily
    cat > /etc/cron.daily/pterodactyl-backup << 'EOF'
#!/bin/bash
BACKUP_DIR="/var/lib/pterodactyl/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup database
mysqldump panel > $BACKUP_DIR/panel_db_$DATE.sql 2>/dev/null

# Backup files panel
tar -czf $BACKUP_DIR/panel_files_$DATE.tar.gz /var/www/pterodactyl 2>/dev/null

# Backup configuration
cp /etc/pterodactyl/config.yml $BACKUP_DIR/wings_config_$DATE.yml 2>/dev/null

# Hapus backup lebih dari 7 hari
find $BACKUP_DIR -type f -mtime +7 -delete

echo "Backup completed on $DATE" >> /var/log/pterodactyl-backup.log
EOF
    
    chmod +x /etc/cron.daily/pterodactyl-backup
    
    log "Cron jobs berhasil disetup"
}

# Fungsi install SSL dengan Let's Encrypt
install_ssl() {
    echo -e "${YELLOW}╔════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║   INSTALL SSL LET'S ENCRYPT            ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Apakah Anda ingin menginstal SSL Let's Encrypt? (y/n): " INSTALL_SSL
    
    if [[ $INSTALL_SSL =~ ^[Yy]$ ]]; then
        log "Menginstal SSL Let's Encrypt..."
        
        # Install certbot
        apt-get install -y certbot python3-certbot-nginx >> "$LOG_FILE" 2>&1
        
        echo ""
        echo -e "Domain panel Anda: ${GREEN}$PANEL_FQDN${NC}"
        read -p "Masukkan email untuk sertifikat SSL (default: $AUTO_EMAIL): " SSL_EMAIL
        SSL_EMAIL=${SSL_EMAIL:-$AUTO_EMAIL}
        
        # Dapatkan sertifikat SSL
        if certbot --nginx -d $PANEL_FQDN --non-interactive --agree-tos --email $SSL_EMAIL >> "$LOG_FILE" 2>&1; then
            log "SSL berhasil diinstal untuk $PANEL_FQDN"
            
            # Update panel URL di database untuk HTTPS
            cd /var/www/pterodactyl
            php artisan p:environment:setup --url=https://$PANEL_FQDN --force >> "$LOG_FILE" 2>&1
            
            # Setup auto-renewal
            echo "0 3 * * * /usr/bin/certbot renew --quiet" | crontab -
            
            echo -e "${GREEN}SSL berhasil diinstal!${NC}"
            echo -e "Panel sekarang dapat diakses via: ${YELLOW}https://$PANEL_FQDN${NC}"
        else
            echo -e "${RED}Gagal menginstal SSL. Pastikan DNS sudah mengarah ke server ini.${NC}"
            echo -e "Anda tetap dapat mengakses panel via: ${YELLOW}http://$PANEL_FQDN${NC}"
        fi
    else
        log "Melewati instalasi SSL"
        echo -e "Panel dapat diakses via: ${YELLOW}http://$PANEL_FQDN${NC}"
    fi
}

# Fungsi untuk menampilkan informasi setelah instalasi
show_post_install_info() {
    show_header
    
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          INSTALASI BERHASIL SELESAI!            ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}=== INFORMASI LOGIN ===${NC}"
    echo -e "Panel URL:  ${YELLOW}http://$PANEL_FQDN${NC}"
    echo -e "Email:      ${GREEN}$AUTO_EMAIL${NC}"
    echo -e "Username:   ${GREEN}$AUTO_USERNAME${NC}"
    echo -e "Password:   ${GREEN}$AUTO_PASSWORD${NC}"
    echo ""
    echo -e "${BLUE}=== FILE INFORMASI ===${NC}"
    echo -e "Credentials:  ${YELLOW}/root/pterodactyl_admin_credentials.txt${NC}"
    echo -e "Database Info: ${YELLOW}/root/pterodactyl_db_info.txt${NC}"
    echo -e "Log Installer: ${YELLOW}$LOG_FILE${NC}"
    echo ""
    echo -e "${BLUE}=== LANGKAH SELANJUTNYA ===${NC}"
    echo "1. Login ke panel dengan credentials di atas"
    echo "2. Ganti password setelah login pertama"
    echo "3. Buat API key di Admin -> Configuration"
    echo "4. Setup node dan location"
    echo "5. Setup Wings dengan API key yang dibuat"
    echo ""
    echo -e "${RED}=== PERINGATAN ===${NC}"
    echo "1. Simpan credentials dengan aman!"
    echo "2. Setup backup rutin"
    echo "3. Monitor log di /var/log/pterodactyl/"
    echo ""
    echo -e "${BLUE}=== STATUS SERVICES ===${NC}"
    systemctl status nginx --no-pager
    echo ""
    systemctl status mariadb --no-pager
    echo ""
    systemctl status wings --no-pager 2>/dev/null || echo "Wings tidak diinstal"
    echo ""
    
    # Tampilkan IP server
    SERVER_IP=$(curl -s ifconfig.me)
    echo -e "Server IP: ${GREEN}$SERVER_IP${NC}"
    echo -e "Port yang terbuka: ${YELLOW}22, 80, 443, 2022, 8080${NC}"
}

# Fungsi main untuk instalasi lengkap
install_complete() {
    show_header
    echo -e "${GREEN}Memulai instalasi Pterodactyl lengkap...${NC}"
    echo -e "Konfigurasi otomatis: ${YELLOW}$AUTO_USERNAME / $AUTO_PASSWORD${NC}"
    echo ""
    
    # Jalankan semua fungsi
    update_system
    install_dependencies
    configure_database
    install_panel
    configure_nginx
    install_wings
    configure_firewall
    setup_cron
    install_ssl
    
    # Tampilkan informasi setelah instalasi
    show_post_install_info
}

# Fungsi untuk instalasi panel saja
install_panel_only() {
    show_header
    echo -e "${GREEN}Memulai instalasi Panel saja...${NC}"
    
    update_system
    install_dependencies
    configure_database
    install_panel
    configure_nginx
    configure_firewall
    setup_cron
    install_ssl
    
    show_post_install_info
}

# Fungsi untuk instalasi wings saja
install_wings_only() {
    show_header
    echo -e "${GREEN}Memulai instalasi Wings saja...${NC}"
    
    update_system
    install_wings
    configure_firewall
    
    echo -e "${GREEN}Wings berhasil diinstal!${NC}"
    echo ""
    echo -e "${BLUE}=== INFORMASI WINGS ===${NC}"
    echo -e "Config: ${YELLOW}/etc/pterodactyl/config.yml${NC}"
    echo -e "Log: ${YELLOW}/var/log/pterodactyl/wings.log${NC}"
    echo ""
    echo -e "${YELLOW}Catatan: Anda perlu menghubungkan Wings ke panel dengan API key${NC}"
}

# Fungsi tampilan menu utama
main_menu() {
    while true; do
        show_header
        echo -e "${GREEN}PILIH JENIS INSTALASI:${NC}"
        echo ""
        echo -e "${BLUE}KONFIGURASI OTOMATIS AKTIF:${NC}"
        echo -e "Email: ${YELLOW}$AUTO_EMAIL${NC}"
        echo -e "User:  ${YELLOW}$AUTO_USERNAME${NC}"
        echo -e "Pass:  ${YELLOW}$AUTO_PASSWORD${NC}"
        echo ""
        echo "1. Install LENGKAP (Panel + Wings)"
        echo "2. Install PANEL saja"
        echo "3. Install WINGS saja"
        echo "4. Install SSL Let's Encrypt"
        echo "5. Cek Status Services"
        echo "6. Tampilkan Informasi Login"
        echo "7. Keluar"
        echo ""
        read -p "Pilihan [1-7]: " choice
        
        case $choice in
            1)
                install_complete
                ;;
            2)
                install_panel_only
                ;;
            3)
                install_wings_only
                ;;
            4)
                install_ssl
                ;;
            5)
                show_header
                echo -e "${GREEN}Status Services:${NC}"
                echo ""
                systemctl status nginx mariadb wings --no-pager
                ;;
            6)
                if [[ -f /root/pterodactyl_admin_credentials.txt ]]; then
                    cat /root/pterodactyl_admin_credentials.txt
                else
                    echo -e "${RED}Panel belum terinstal!${NC}"
                fi
                ;;
            7)
                echo -e "${GREEN}Keluar...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Pilihan tidak valid!${NC}"
                ;;
        esac
        
        echo ""
        echo -e "${YELLOW}Tekan Enter untuk melanjutkan...${NC}"
        read -r
    done
}

# Jalankan script
check_root
check_ubuntu_version
main_menu

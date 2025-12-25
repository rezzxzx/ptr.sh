#!/bin/bash

##############################################
# Pterodactyl Panel Auto Installer
# Support: Ubuntu 24.04, 22.04, 20.04
# Author: Auto Installer Script
##############################################

set -e

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Fungsi print
print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${GREEN}[i]${NC} $1"
}

# Check root
if [[ $EUID -ne 0 ]]; then
   print_error "Script ini harus dijalankan sebagai root!"
   exit 1
fi

# Deteksi versi Ubuntu
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    print_error "Tidak dapat mendeteksi versi OS"
    exit 1
fi

if [[ "$OS" != "ubuntu" ]]; then
    print_error "Script ini hanya untuk Ubuntu!"
    exit 1
fi

if [[ ! "$VER" =~ ^(20.04|22.04|24.04)$ ]]; then
    print_error "Versi Ubuntu tidak didukung. Hanya mendukung 20.04, 22.04, dan 24.04"
    exit 1
fi

print_success "Terdeteksi: Ubuntu $VER"

# Konfigurasi
echo ""
print_info "=== KONFIGURASI PTERODACTYL PANEL ==="

# Input FQDN (manual)
read -p "Masukkan FQDN/Domain (contoh: panel.domain.com): " FQDN

# Konfigurasi Otomatis Lainnya
TIMEZONE="Asia/Jakarta"
EMAIL="ryezx@gmail.com"
ADMIN_USER="ryezx"
ADMIN_PASS="ryezx"
MYSQL_ROOT_PASS="ryezx$(openssl rand -hex 4)"
MYSQL_PTERO_PASS="ryezx$(openssl rand -hex 4)"

# Tampilkan konfigurasi
echo ""
print_success "Konfigurasi yang akan digunakan:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "FQDN/Domain : $FQDN"
echo "Timezone    : $TIMEZONE"
echo "Email       : $EMAIL"
echo "Username    : $ADMIN_USER"
echo "Password    : $ADMIN_PASS"
echo "MySQL Root  : $MYSQL_ROOT_PASS"
echo "MySQL Panel : $MYSQL_PTERO_PASS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_warning "Instalasi akan dimulai dalam 5 detik..."
print_warning "Tekan Ctrl+C untuk membatalkan"
sleep 5

# Update sistem
print_info "Mengupdate sistem..."
apt update && apt upgrade -y
print_success "Sistem berhasil diupdate"

# Install dependencies
print_info "Menginstall dependencies..."
apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
apt update
print_success "Dependencies terinstall"

# Install PHP 8.3 dan extensions
print_info "Menginstall PHP 8.3..."
apt install -y php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip}
print_success "PHP 8.3 terinstall"

# Install Composer
print_info "Menginstall Composer..."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
print_success "Composer terinstall"

# Install dan konfigurasi MySQL
print_info "Menginstall MySQL..."
apt install -y mysql-server
systemctl enable mysql
systemctl start mysql
print_success "MySQL terinstall"

print_info "Mengkonfigurasi MySQL..."
# Set root password dengan cara yang lebih aman
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';" 2>/dev/null || \
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';"

# Buat database dan user
mysql -uroot -p${MYSQL_ROOT_PASS} -e "DROP DATABASE IF EXISTS panel;"
mysql -uroot -p${MYSQL_ROOT_PASS} -e "CREATE DATABASE panel;"
mysql -uroot -p${MYSQL_ROOT_PASS} -e "DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';"
mysql -uroot -p${MYSQL_ROOT_PASS} -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PTERO_PASS}';"
mysql -uroot -p${MYSQL_ROOT_PASS} -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
mysql -uroot -p${MYSQL_ROOT_PASS} -e "FLUSH PRIVILEGES;"
print_success "MySQL dikonfigurasi"

# Install Redis
print_info "Menginstall Redis..."
apt install -y redis-server
systemctl enable redis-server
systemctl start redis-server
print_success "Redis terinstall"

# Download Pterodactyl
print_info "Mendownload Pterodactyl Panel..."
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/
print_success "Pterodactyl Panel didownload"

# Install dependencies Pterodactyl
print_info "Menginstall dependencies Pterodactyl..."
cp .env.example .env
composer install --no-dev --optimize-autoloader --no-interaction
print_success "Dependencies terinstall"

# Setup environment
print_info "Mengkonfigurasi environment..."
php artisan key:generate --force
php artisan p:environment:setup \
    --author=${EMAIL} \
    --url=https://${FQDN} \
    --timezone=${TIMEZONE} \
    --cache=redis \
    --session=redis \
    --queue=redis \
    --redis-host=127.0.0.1 \
    --redis-pass= \
    --redis-port=6379 \
    --no-interaction

php artisan p:environment:database \
    --host=127.0.0.1 \
    --port=3306 \
    --database=panel \
    --username=pterodactyl \
    --password=${MYSQL_PTERO_PASS} \
    --no-interaction

print_success "Environment dikonfigurasi"

# Migrasi database
print_info "Melakukan migrasi database..."
php artisan migrate --seed --force
print_success "Database berhasil dimigrasi"

# Buat user admin
print_info "Membuat user admin..."
php artisan p:user:make \
    --email=${EMAIL} \
    --username=${ADMIN_USER} \
    --name-first=Admin \
    --name-last=User \
    --password=${ADMIN_PASS} \
    --admin=1 \
    --no-interaction
print_success "User admin dibuat"

# Set permissions
print_info "Mengatur permissions..."
chown -R www-data:www-data /var/www/pterodactyl/*
print_success "Permissions diatur"

# Setup Cron
print_info "Mengatur Cron job..."
(crontab -l 2>/dev/null; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -
print_success "Cron job diatur"

# Setup Queue Worker
print_info "Mengatur Queue Worker..."
cat > /etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl enable pteroq.service
systemctl start pteroq.service
print_success "Queue Worker diatur"

# Install Nginx
print_info "Menginstall Nginx..."
apt install -y nginx
print_success "Nginx terinstall"

# Konfigurasi Nginx
print_info "Mengkonfigurasi Nginx..."
cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${FQDN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${FQDN};

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    # SSL akan dikonfigurasi dengan Certbot
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
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

ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx
print_success "Nginx dikonfigurasi"

# Install Certbot untuk SSL
print_info "Menginstall Certbot untuk SSL..."
apt install -y certbot python3-certbot-nginx
print_success "Certbot terinstall"

print_info "Mendapatkan SSL certificate untuk ${FQDN}..."
certbot --nginx -d ${FQDN} --non-interactive --agree-tos -m ${EMAIL} --redirect || print_warning "SSL gagal dikonfigurasi otomatis. Pastikan domain sudah mengarah ke server ini, lalu jalankan: certbot --nginx -d ${FQDN}"

# Setup firewall (opsional)
print_info "Mengkonfigurasi firewall..."
if command -v ufw &> /dev/null; then
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
    print_success "Firewall dikonfigurasi"
fi

# Selesai
echo ""
echo "======================================"
print_success "INSTALASI SELESAI!"
echo "======================================"
echo ""
print_info "Informasi Login Panel:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "URL      : https://${FQDN}"
echo "Username : ${ADMIN_USER}"
echo "Password : ${ADMIN_PASS}"
echo "Email    : ${EMAIL}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
print_warning "Informasi Database (SIMPAN INI!):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "MySQL Root Password : ${MYSQL_ROOT_PASS}"
echo "Database Password   : ${MYSQL_PTERO_PASS}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
print_info "Langkah Selanjutnya:"
echo "1. Pastikan domain ${FQDN} sudah mengarah ke server ini"
echo "2. Akses panel di: https://${FQDN}"
echo "3. Login dengan username dan password di atas"
echo "4. Install Wings untuk membuat node server"
echo ""
print_success "Selamat! Panel Pterodactyl siap digunakan!"
echo ""

# Simpan kredensial ke file
cat > /root/pterodactyl-credentials.txt <<EOF
====================================
PTERODACTYL PANEL CREDENTIALS
====================================
Tanggal Install: $(date)

Panel URL    : https://${FQDN}
Username     : ${ADMIN_USER}
Password     : ${ADMIN_PASS}
Email        : ${EMAIL}

MySQL Root   : ${MYSQL_ROOT_PASS}
Database Pass: ${MYSQL_PTERO_PASS}

Location: /var/www/pterodactyl
EOF

print_success "Kredensial disimpan di: /root/pterodactyl-credentials.txt"

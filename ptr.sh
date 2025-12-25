#!/bin/bash

##############################################
# Pterodactyl Panel Auto Installer
# Support: Ubuntu 24.04, 22.04, 20.04
# Version: 2.0 - Bug Free Edition
##############################################

set -e

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    echo -e "${BLUE}[i]${NC} $1"
}

print_break() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Fungsi untuk error handling
error_exit() {
    print_error "$1"
    print_error "Instalasi dibatalkan!"
    exit 1
}

# Check root
if [[ $EUID -ne 0 ]]; then
   error_exit "Script ini harus dijalankan sebagai root! Gunakan: sudo ./ptr.sh"
fi

# Banner
clear
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║                                                       ║
║        PTERODACTYL PANEL AUTO INSTALLER v2.0         ║
║              Bug Free Edition - 2024                  ║
║                                                       ║
╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Deteksi versi Ubuntu
print_info "Mendeteksi sistem operasi..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    error_exit "Tidak dapat mendeteksi versi OS"
fi

if [[ "$OS" != "ubuntu" ]]; then
    error_exit "Script ini hanya untuk Ubuntu! OS terdeteksi: $OS"
fi

if [[ ! "$VER" =~ ^(20.04|22.04|24.04)$ ]]; then
    error_exit "Versi Ubuntu tidak didukung. Hanya mendukung 20.04, 22.04, dan 24.04"
fi

print_success "OS terdeteksi: Ubuntu $VER"
sleep 1

# Konfigurasi
print_break
echo -e "${GREEN}KONFIGURASI PTERODACTYL PANEL${NC}"
print_break

# Input FQDN (manual)
while true; do
    read -p "Masukkan FQDN/Domain (contoh: panel.domain.com): " FQDN
    if [[ -z "$FQDN" ]]; then
        print_error "FQDN tidak boleh kosong!"
        continue
    fi
    # Validasi format domain (basic)
    if [[ ! "$FQDN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        print_warning "Format domain tidak valid. Contoh: panel.domain.com"
        continue
    fi
    break
done

# Konfigurasi Otomatis
TIMEZONE="Asia/Jakarta"
EMAIL="ryezx@gmail.com"
ADMIN_USER="ryezx"
ADMIN_PASS="ryezx"
ADMIN_FIRSTNAME="Admin"
ADMIN_LASTNAME="User"
MYSQL_ROOT_PASS="Ryezx$(openssl rand -hex 6)"
MYSQL_PTERO_PASS="Ptero$(openssl rand -hex 6)"

# Tampilkan konfigurasi
echo ""
print_success "Konfigurasi yang akan digunakan:"
print_break
echo -e "${GREEN}FQDN/Domain${NC} : $FQDN"
echo -e "${GREEN}Timezone${NC}    : $TIMEZONE"
echo -e "${GREEN}Email Admin${NC} : $EMAIL"
echo -e "${GREEN}Username${NC}    : $ADMIN_USER"
echo -e "${GREEN}Password${NC}    : $ADMIN_PASS"
echo -e "${GREEN}MySQL Root${NC}  : $MYSQL_ROOT_PASS"
echo -e "${GREEN}MySQL Panel${NC} : $MYSQL_PTERO_PASS"
print_break
echo ""

print_warning "Instalasi akan dimulai dalam 5 detik..."
print_warning "Tekan Ctrl+C untuk membatalkan"
sleep 5

# Update sistem
print_break
print_info "Step 1/12: Mengupdate sistem..."
print_break
export DEBIAN_FRONTEND=noninteractive
apt update -qq > /dev/null 2>&1 || error_exit "Gagal update repository"
apt upgrade -y -qq > /dev/null 2>&1 || error_exit "Gagal upgrade sistem"
print_success "Sistem berhasil diupdate"
sleep 1

# Install dependencies
print_break
print_info "Step 2/12: Menginstall dependencies..."
print_break
apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release > /dev/null 2>&1 || error_exit "Gagal install dependencies dasar"

# Add PHP repository
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1 || error_exit "Gagal menambahkan PHP repository"
apt update -qq > /dev/null 2>&1
print_success "Dependencies terinstall"
sleep 1

# Install PHP 8.3 dan extensions
print_break
print_info "Step 3/12: Menginstall PHP 8.3 dan extensions..."
print_break
apt install -y php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip,intl} > /dev/null 2>&1 || error_exit "Gagal install PHP 8.3"

# Set PHP 8.3 sebagai default
update-alternatives --set php /usr/bin/php8.3 > /dev/null 2>&1

# Verifikasi PHP
PHP_VERSION=$(php -r "echo PHP_VERSION;" | cut -d. -f1,2)
if [[ "$PHP_VERSION" != "8.3" ]]; then
    error_exit "PHP version tidak sesuai. Terdeteksi: $PHP_VERSION"
fi

print_success "PHP 8.3 terinstall ($(php -r 'echo PHP_VERSION;'))"
sleep 1

# Install Composer
print_break
print_info "Step 4/12: Menginstall Composer..."
print_break
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer > /dev/null 2>&1 || error_exit "Gagal install Composer"
print_success "Composer terinstall ($(composer --version --no-ansi | head -n1))"
sleep 1

# Install MySQL
print_break
print_info "Step 5/12: Menginstall dan konfigurasi MySQL..."
print_break

# Stop MySQL jika sudah ada
systemctl stop mysql > /dev/null 2>&1 || true

# Install MySQL
apt install -y mysql-server > /dev/null 2>&1 || error_exit "Gagal install MySQL"

# Start MySQL
systemctl enable mysql > /dev/null 2>&1
systemctl start mysql > /dev/null 2>&1

# Tunggu MySQL siap
print_info "Menunggu MySQL siap..."
for i in {1..30}; do
    if mysqladmin ping > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Cek apakah MySQL running
if ! systemctl is-active --quiet mysql; then
    error_exit "MySQL gagal start! Cek: systemctl status mysql"
fi

if ! mysqladmin ping > /dev/null 2>&1; then
    error_exit "MySQL tidak merespon! Cek: tail /var/log/mysql/error.log"
fi

print_success "MySQL terinstall dan berjalan"
sleep 1

# Konfigurasi MySQL
print_info "Mengkonfigurasi MySQL database dan user..."

# Set root password
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';" 2>/dev/null || \
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';" || \
error_exit "Gagal set MySQL root password"

# Drop existing database dan user jika ada
mysql -uroot -p${MYSQL_ROOT_PASS} -e "DROP DATABASE IF EXISTS panel;" 2>/dev/null
mysql -uroot -p${MYSQL_ROOT_PASS} -e "DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';" 2>/dev/null

# Buat database baru
mysql -uroot -p${MYSQL_ROOT_PASS} -e "CREATE DATABASE panel;" || error_exit "Gagal membuat database"

# Buat user baru
mysql -uroot -p${MYSQL_ROOT_PASS} -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PTERO_PASS}';" || error_exit "Gagal membuat user MySQL"

# Grant privileges
mysql -uroot -p${MYSQL_ROOT_PASS} -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;" || error_exit "Gagal grant privileges"

mysql -uroot -p${MYSQL_ROOT_PASS} -e "FLUSH PRIVILEGES;" || error_exit "Gagal flush privileges"

# Test koneksi database
mysql -upterodactyl -p${MYSQL_PTERO_PASS} -h127.0.0.1 -e "USE panel;" > /dev/null 2>&1 || error_exit "Gagal test koneksi database pterodactyl"

print_success "MySQL database dan user dikonfigurasi"
sleep 1

# Install Redis
print_break
print_info "Step 6/12: Menginstall Redis..."
print_break
apt install -y redis-server > /dev/null 2>&1 || error_exit "Gagal install Redis"
systemctl enable redis-server > /dev/null 2>&1
systemctl start redis-server > /dev/null 2>&1

# Cek Redis
if ! systemctl is-active --quiet redis-server; then
    error_exit "Redis gagal start!"
fi

print_success "Redis terinstall dan berjalan"
sleep 1

# Download Pterodactyl
print_break
print_info "Step 7/12: Mendownload Pterodactyl Panel..."
print_break

# Hapus jika sudah ada
rm -rf /var/www/pterodactyl

mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl

# Download dengan retry
DOWNLOAD_SUCCESS=0
for i in {1..3}; do
    if curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz; then
        DOWNLOAD_SUCCESS=1
        break
    fi
    print_warning "Download gagal, mencoba lagi... ($i/3)"
    sleep 2
done

if [[ $DOWNLOAD_SUCCESS -eq 0 ]]; then
    error_exit "Gagal download Pterodactyl Panel setelah 3 percobaan"
fi

tar -xzvf panel.tar.gz > /dev/null 2>&1 || error_exit "Gagal extract panel.tar.gz"
rm panel.tar.gz

chmod -R 755 storage/* bootstrap/cache/ || error_exit "Gagal set permissions"

print_success "Pterodactyl Panel didownload"
sleep 1

# Install dependencies Pterodactyl
print_break
print_info "Step 8/12: Menginstall dependencies Pterodactyl..."
print_break

cp .env.example .env || error_exit "Gagal copy .env.example"

# Install composer dependencies dengan proper flags
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction > /dev/null 2>&1 || error_exit "Gagal install dependencies composer"

print_success "Dependencies Pterodactyl terinstall"
sleep 1

# Setup environment
print_break
print_info "Step 9/12: Mengkonfigurasi environment Pterodactyl..."
print_break

# Generate app key
php artisan key:generate --force || error_exit "Gagal generate app key"

# Setup environment
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
    --no-interaction || error_exit "Gagal setup environment"

# Setup database
php artisan p:environment:database \
    --host=127.0.0.1 \
    --port=3306 \
    --database=panel \
    --username=pterodactyl \
    --password=${MYSQL_PTERO_PASS} \
    --no-interaction || error_exit "Gagal setup database environment"

print_success "Environment dikonfigurasi"
sleep 1

# Migrasi database
print_break
print_info "Step 10/12: Melakukan migrasi database..."
print_break

php artisan migrate --seed --force || error_exit "Gagal migrasi database"

print_success "Database berhasil dimigrasi"
sleep 1

# Buat user admin
print_break
print_info "Step 11/12: Membuat user admin..."
print_break

php artisan p:user:make \
    --email=${EMAIL} \
    --username=${ADMIN_USER} \
    --name-first=${ADMIN_FIRSTNAME} \
    --name-last=${ADMIN_LASTNAME} \
    --password=${ADMIN_PASS} \
    --admin=1 \
    --no-interaction || error_exit "Gagal membuat user admin"

print_success "User admin berhasil dibuat"
sleep 1

# Set permissions
print_info "Mengatur file permissions..."
chown -R www-data:www-data /var/www/pterodactyl/* || error_exit "Gagal set ownership"
print_success "Permissions diatur"
sleep 1

# Setup Cron
print_info "Mengatur Cron job..."
(crontab -l 2>/dev/null | grep -v "pterodactyl/artisan schedule:run"; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab - || error_exit "Gagal setup cron"
print_success "Cron job diatur"
sleep 1

# Setup Queue Worker
print_info "Mengatur Queue Worker service..."
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

systemctl daemon-reload
systemctl enable pteroq.service > /dev/null 2>&1
systemctl start pteroq.service || error_exit "Gagal start Queue Worker"

# Cek queue worker
if ! systemctl is-active --quiet pteroq.service; then
    print_warning "Queue Worker gagal start, tapi instalasi dilanjutkan"
else
    print_success "Queue Worker berjalan"
fi
sleep 1

# Install Nginx
print_break
print_info "Step 12/12: Menginstall dan konfigurasi Nginx..."
print_break

apt install -y nginx > /dev/null 2>&1 || error_exit "Gagal install Nginx"

# Hapus config default
rm -f /etc/nginx/sites-enabled/default

# Konfigurasi Nginx
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

    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers off;

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
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Enable site
ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf

# Test Nginx config
nginx -t > /dev/null 2>&1 || error_exit "Nginx config error! Jalankan: nginx -t"

# Restart Nginx
systemctl restart nginx || error_exit "Gagal restart Nginx"
systemctl enable nginx > /dev/null 2>&1

print_success "Nginx dikonfigurasi"
sleep 1

# Install Certbot untuk SSL
print_break
print_info "Menginstall SSL Certificate (Let's Encrypt)..."
print_break

apt install -y certbot python3-certbot-nginx > /dev/null 2>&1 || print_warning "Gagal install Certbot"

print_info "Mendapatkan SSL certificate untuk ${FQDN}..."
print_warning "Pastikan domain ${FQDN} sudah mengarah ke server ini!"
sleep 2

certbot --nginx -d ${FQDN} --non-interactive --agree-tos -m ${EMAIL} --redirect 2>/dev/null && print_success "SSL certificate berhasil diinstall!" || print_warning "SSL gagal diinstall otomatis. Jalankan manual: certbot --nginx -d ${FQDN}"

# Setup firewall (opsional)
if command -v ufw &> /dev/null; then
    print_info "Mengkonfigurasi firewall..."
    ufw --force reset > /dev/null 2>&1
    ufw default deny incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1
    ufw allow 22/tcp > /dev/null 2>&1
    ufw allow 80/tcp > /dev/null 2>&1
    ufw allow 443/tcp > /dev/null 2>&1
    ufw --force enable > /dev/null 2>&1
    print_success "Firewall dikonfigurasi"
fi

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
Database User: pterodactyl
Database Pass: ${MYSQL_PTERO_PASS}
Database Name: panel

Panel Path   : /var/www/pterodactyl
Nginx Config : /etc/nginx/sites-available/pterodactyl.conf

====================================
NEXT STEPS:
====================================
1. Akses panel di: https://${FQDN}
2. Login dengan username dan password di atas
3. Install Wings untuk membuat node server:
   https://pterodactyl.io/wings/1.0/installing.html

====================================
TROUBLESHOOTING:
====================================
- Cek Queue Worker: systemctl status pteroq
- Cek Nginx: systemctl status nginx
- Cek PHP-FPM: systemctl status php8.3-fpm
- Cek MySQL: systemctl status mysql
- Cek Redis: systemctl status redis-server
- Cek Nginx Error: tail -f /var/log/nginx/pterodactyl.app-error.log

EOF

# Selesai
clear
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║                                                       ║
║            INSTALASI BERHASIL SELESAI!               ║
║                                                       ║
╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

print_break
echo -e "${GREEN}INFORMASI LOGIN PANEL${NC}"
print_break
echo -e "${GREEN}URL      :${NC} https://${FQDN}"
echo -e "${GREEN}Username :${NC} ${ADMIN_USER}"
echo -e "${GREEN}Password :${NC} ${ADMIN_PASS}"
echo -e "${GREEN}Email    :${NC} ${EMAIL}"
print_break
echo ""
print_warning "INFORMASI DATABASE (SIMPAN INI!)"
print_break
echo -e "${YELLOW}MySQL Root Password :${NC} ${MYSQL_ROOT_PASS}"
echo -e "${YELLOW}Database Password   :${NC} ${MYSQL_PTERO_PASS}"
print_break
echo ""
print_info "📄 Kredensial lengkap disimpan di: ${GREEN}/root/pterodactyl-credentials.txt${NC}"
echo ""
print_success "✨ Panel Pterodactyl siap digunakan!"
echo ""
print_info "🔗 Akses panel Anda di: ${GREEN}https://${FQDN}${NC}"
echo ""
print_warning "📚 Langkah selanjutnya: Install Wings untuk membuat node server"
echo "   Dokumentasi: https://pterodactyl.io/wings/1.0/installing.html"
echo ""
print_break

# Service status check
echo ""
print_info "Status Services:"
systemctl is-active --quiet nginx && echo -e "  Nginx     : ${GREEN}✓ Running${NC}" || echo -e "  Nginx     : ${RED}✗ Stopped${NC}"
systemctl is-active --quiet mysql && echo -e "  MySQL     : ${GREEN}✓ Running${NC}" || echo -e "  MySQL     : ${RED}✗ Stopped${NC}"
systemctl is-active --quiet redis-server && echo -e "  Redis     : ${GREEN}✓ Running${NC}" || echo -e "  Redis     : ${RED}✗ Stopped${NC}"
systemctl is-active --quiet php8.3-fpm && echo -e "  PHP-FPM   : ${GREEN}✓ Running${NC}" || echo -e "  PHP-FPM   : ${RED}✗ Stopped${NC}"
systemctl is-active --quiet pteroq && echo -e "  Queue     : ${GREEN}✓ Running${NC}" || echo -e "  Queue     : ${RED}✗ Stopped${NC}"
echo ""
print_break

exit 0

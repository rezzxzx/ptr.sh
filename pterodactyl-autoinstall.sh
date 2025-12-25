#!/bin/bash

# ============================================
# PTERODACTYL INSTALLER SCRIPT
# Versi: 2.0.0
# Dukungan: Ubuntu 20.04/22.04, Debian 11/12
# ============================================

# Clear screen
clear

# Warna untuk UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Variabel global
PANEL_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
WINGS_URL="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64"
MYSQL_ROOT_PASS=$(openssl rand -base64 32)
PANEL_URL_SETUP="http://$(curl -4 -s ifconfig.co)"

# Fungsi untuk menampilkan header
show_header() {
    clear
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║    ██████╗ ████████╗███████║██████╗  ██████╗ █████╗  ██████╗ ║"
    echo "║    ██╔══██╗╚══██╔══╝██╔════╝██╔══██╗██╔═══██╗██╔══██╗██╔══██╗║"
    echo "║    ██████╔╝   ██║   █████║  ██║  ██║██║   ██║███████║██████╔╝║"
    echo "║    ██╔═══╝    ██║   ██╔══║  ██║  ██║██║   ██║██╔══██║██╔══██╗║"
    echo "║    ██║        ██║   ███████║██████╔╝╚██████╔╝██║  ██║██║  ██║║"
    echo "║    ╚═╝        ╚═╝   ╚══════╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝║"
    echo "║                   INSTALLER SCRIPT v2.0.0                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Fungsi untuk progress bar
progress_bar() {
    local duration=${1}
    local increment=$((100/$duration))
    local elapsed=0
    local bar=""
    
    while [ $elapsed -le $duration ]; do
        printf -v prog "%0.s#" $(seq 1 $((elapsed*50/duration)))
        printf -v space "%0.s " $(seq 1 $((50-(elapsed*50/duration))))
        printf "[${GREEN}%s${space}${NC}] %3d%%" "$prog" $((elapsed*100/duration))
        sleep 1
        elapsed=$((elapsed + 1))
        printf "\r"
    done
    echo "[${GREEN}##################################################${NC}] 100%"
}

# Fungsi untuk cek root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: Script ini harus dijalankan sebagai root!${NC}"
        echo -e "${YELLOW}Gunakan: sudo bash install.sh${NC}"
        exit 1
    fi
}

# Fungsi untuk cek OS
check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        echo -e "${RED}Tidak dapat mendeteksi OS!${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}✓ Sistem Operasi: $OS $VER${NC}"
    
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        echo -e "${RED}Error: OS ini tidak didukung!${NC}"
        echo -e "${YELLOW}Hanya Ubuntu 20.04/22.04 dan Debian 11/12 yang didukung${NC}"
        exit 1
    fi
}

# Fungsi untuk update system
update_system() {
    echo -e "\n${BLUE}[1/10]${NC} Memperbarui sistem..."
    progress_bar 3
    
    apt-get update > /dev/null 2>&1
    apt-get -y upgrade > /dev/null 2>&1
    apt-get -y autoremove > /dev/null 2>&1
    
    echo -e "${GREEN}✓ Sistem telah diperbarui${NC}"
}

# Fungsi untuk install dependencies
install_dependencies() {
    echo -e "\n${BLUE}[2/10]${NC} Menginstal dependencies..."
    progress_bar 5
    
    apt-get -y install software-properties-common curl apt-transport-https ca-certificates gnupg > /dev/null 2>&1
    
    # PHP repositori
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1
    
    # MariaDB repositori
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash > /dev/null 2>&1
    
    apt-get update > /dev/null 2>&1
    
    # Install dependencies panel
    apt-get -y install php8.1 php8.1-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} \
        mariadb-server nginx tar unzip git redis-server \
        cron composer > /dev/null 2>&1
    
    echo -e "${GREEN}✓ Dependencies berhasil diinstal${NC}"
}

# Fungsi untuk konfigurasi database
configure_database() {
    echo -e "\n${BLUE}[3/10]${NC} Mengkonfigurasi database..."
    progress_bar 4
    
    # Secure MySQL installation
    mysql -e "DELETE FROM mysql.user WHERE User='';"
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -e "DROP DATABASE IF EXISTS test;"
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    mysql -e "FLUSH PRIVILEGES;"
    
    # Buat database untuk panel
    mysql -e "CREATE DATABASE panel;"
    mysql -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${MYSQL_ROOT_PASS}';"
    mysql -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -e "FLUSH PRIVILEGES;"
    
    echo -e "${GREEN}✓ Database berhasil dikonfigurasi${NC}"
}

# Fungsi untuk install panel
install_panel() {
    echo -e "\n${BLUE}[4/10]${NC} Mengunduh panel..."
    progress_bar 3
    
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    
    curl -L $PANEL_URL | tar -xz > /dev/null 2>&1
    chmod -R 755 storage/* bootstrap/cache/
    
    echo -e "\n${BLUE}[5/10]${NC} Menginstal dependencies composer..."
    progress_bar 8
    
    composer install --no-dev --optimize-autoloader > /dev/null 2>&1
    
    echo -e "\n${BLUE}[6/10]${NC} Mengkonfigurasi environment..."
    progress_bar 3
    
    cp .env.example .env
    php artisan key:generate --force > /dev/null 2>&1
    
    # Update .env file
    sed -i "s/DB_PASSWORD=/DB_PASSWORD=${MYSQL_ROOT_PASS}/g" .env
    sed -i "s/APP_URL=http:\/\/localhost/APP_URL=${PANEL_URL_SETUP}/g" .env
    
    echo -e "\n${BLUE}[7/10]${NC} Migrasi database..."
    progress_bar 5
    
    php artisan p:environment:setup \
        --author=admin@localhost \
        --url=$PANEL_URL_SETUP \
        --timezone=Asia/Jakarta \
        --cache=redis \
        --session=redis \
        --queue=redis \
        --redis-host=localhost \
        --redis-pass=null \
        --redis-port=6379 \
        --settings-ui=true > /dev/null 2>&1
    
    php artisan p:environment:database \
        --host=127.0.0.1 \
        --port=3306 \
        --database=panel \
        --username=pterodactyl \
        --password=${MYSQL_ROOT_PASS} > /dev/null 2>&1
    
    php artisan migrate --seed --force > /dev/null 2>&1
    
    echo -e "\n${BLUE}[8/10]${NC} Membuat user admin..."
    progress_bar 2
    
    php artisan p:user:make \
        --email=admin@localhost \
        --username=admin \
        --name=Admin \
        --password=admin123 \
        --admin=1 > /dev/null 2>&1
    
    echo -e "\n${BLUE}[9/10]${NC} Mengkonfigurasi nginx..."
    progress_bar 3
    
    cat > /etc/nginx/sites-available/pterodactyl.conf << 'EOF'
server {
    listen 80;
    server_name _;
    root /var/www/pterodactyl/public;
    
    index index.html index.htm index.php;
    charset utf-8;
    
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size = 100M";
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
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
    rm -f /etc/nginx/sites-enabled/default
    systemctl restart nginx > /dev/null 2>&1
    
    echo -e "\n${BLUE}[10/10]${NC} Mengkonfigurasi cron jobs..."
    progress_bar 2
    
    (crontab -l 2>/dev/null; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -
    
    # Set permissions
    chown -R www-data:www-data /var/www/pterodactyl/*
    
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ PANEL PTERODACTYL BERHASIL DIINSTAL!${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}URL Panel:${NC} ${PANEL_URL_SETUP}"
    echo -e "${YELLOW}Email:${NC} admin@localhost"
    echo -e "${YELLOW}Password:${NC} admin123"
    echo -e "${YELLOW}MySQL Password:${NC} ${MYSQL_ROOT_PASS}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Jangan lupa ganti password default setelah login pertama!${NC}"
}

# Fungsi untuk install wings
install_wings() {
    echo -e "\n${BLUE}[1/8]${NC} Menginstal dependencies Wings..."
    progress_bar 4
    
    apt-get update > /dev/null 2>&1
    apt-get -y install docker.io docker-compose > /dev/null 2>&1
    systemctl enable docker > /dev/null 2>&1
    systemctl start docker > /dev/null 2>&1
    
    echo -e "\n${BLUE}[2/8]${NC} Mengunduh Wings..."
    progress_bar 3
    
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings $WINGS_URL > /dev/null 2>&1
    chmod +x /usr/local/bin/wings
    
    echo -e "\n${BLUE}[3/8]${NC} Membuat konfigurasi Wings..."
    progress_bar 3
    
    cat > /etc/pterodactyl/config.yml << 'EOF'
debug: false
uuid: auto
token: YOUR_PANEL_TOKEN_HERE
api:
  host: 0.0.0.0
  port: 8080
  ssl:
    enabled: false
  upload_limit: 100
system:
  data: /var/lib/pterodactyl/volumes
  sftp:
    port: 2022
allowed_mounts: []
remote: http://your-panel-url.com
EOF
    
    echo -e "\n${BLUE}[4/8]${NC} Membuat service Wings..."
    progress_bar 2
    
    cat > /etc/systemd/system/wings.service << 'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
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
    
    echo -e "\n${BLUE}[5/8]${NC} Membuat direktori data..."
    progress_bar 2
    
    mkdir -p /var/lib/pterodactyl/volumes
    mkdir -p /var/log/pterodactyl
    
    echo -e "\n${BLUE}[6/8]${NC} Reload systemd..."
    progress_bar 2
    
    systemctl daemon-reload > /dev/null 2>&1
    
    echo -e "\n${BLUE}[7/8]${NC} Mengaktifkan Wings..."
    progress_bar 2
    
    systemctl enable wings > /dev/null 2>&1
    
    echo -e "\n${BLUE}[8/8]${NC} Konfigurasi firewall..."
    progress_bar 3
    
    # Setup firewall jika ufw ada
    if command -v ufw &> /dev/null; then
        ufw allow 22/tcp > /dev/null 2>&1
        ufw allow 80/tcp > /dev/null 2>&1
        ufw allow 443/tcp > /dev/null 2>&1
        ufw allow 8080/tcp > /dev/null 2>&1
        ufw allow 2022/tcp > /dev/null 2>&1
        ufw --force enable > /dev/null 2>&1
    fi
    
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ WINGS BERHASIL DIINSTAL!${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Langkah selanjutnya:${NC}"
    echo -e "1. Buka panel Pterodactyl di ${PANEL_URL_SETUP}"
    echo -e "2. Buat location dan node di Admin → Locations & Nodes"
    echo -e "3. Generate configuration untuk node"
    echo -e "4. Copy token dan update di /etc/pterodactyl/config.yml"
    echo -e "5. Jalankan: ${CYAN}systemctl start wings${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
}

# Fungsi untuk menghapus semua
uninstall_all() {
    echo -e "\n${RED}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}PERINGATAN: Ini akan menghapus SEMUA konfigurasi!${NC}"
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    
    read -p "Apakah Anda yakin? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Uninstall dibatalkan.${NC}"
        return
    fi
    
    echo -e "\n${RED}[1/6]${NC} Menghentikan service..."
    progress_bar 3
    
    systemctl stop wings > /dev/null 2>&1 2>/dev/null
    systemctl stop nginx > /dev/null 2>&1
    systemctl stop mariadb > /dev/null 2>&1
    systemctl stop redis-server > /dev/null 2>&1
    
    echo -e "\n${RED}[2/6]${NC} Menghapus panel..."
    progress_bar 4
    
    rm -rf /var/www/pterodactyl > /dev/null 2>&1
    rm -f /etc/nginx/sites-available/pterodactyl.conf > /dev/null 2>&1
    rm -f /etc/nginx/sites-enabled/pterodactyl.conf > /dev/null 2>&1
    
    echo -e "\n${RED}[3/6]${NC} Menghapus wings..."
    progress_bar 3
    
    rm -f /usr/local/bin/wings > /dev/null 2>&1
    rm -rf /etc/pterodactyl > /dev/null 2>&1
    rm -rf /var/lib/pterodactyl > /dev/null 2>&1
    rm -rf /var/log/pterodactyl > /dev/null 2>&1
    rm -f /etc/systemd/system/wings.service > /dev/null 2>&1
    
    echo -e "\n${RED}[4/6]${NC} Menghapus database..."
    progress_bar 3
    
    mysql -e "DROP DATABASE IF EXISTS panel;" > /dev/null 2>&1
    mysql -e "DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';" > /dev/null 2>&1
    mysql -e "FLUSH PRIVILEGES;" > /dev/null 2>&1
    
    echo -e "\n${RED}[5/6]${NC} Menghapus dependencies..."
    progress_bar 5
    
    apt-get -y remove --purge php8.1* mariadb-server nginx redis-server docker.io docker-compose > /dev/null 2>&1
    apt-get -y autoremove > /dev/null 2>&1
    
    echo -e "\n${RED}[6/6]${NC} Membersihkan sistem..."
    progress_bar 3
    
    apt-get clean > /dev/null 2>&1
    rm -rf /var/lib/apt/lists/*
    systemctl daemon-reload > /dev/null 2>&1
    
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ SEMUA KONFIGURASI BERHASIL DIHAPUS!${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
}

# Fungsi untuk menampilkan menu
show_menu() {
    while true; do
        show_header
        echo -e "${CYAN}"
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║                      PILIHAN INSTALLASI                      ║"
        echo "╠══════════════════════════════════════════════════════════════╣"
        echo "║   ${GREEN}1.${CYAN}  Install Panel Pterodactyl                      ║"
        echo "║   ${GREEN}2.${CYAN}  Install Wings (Daemon)                         ║"
        echo "║   ${GREEN}3.${CYAN}  Install Panel + Wings                          ║"
        echo "║   ${RED}4.${CYAN}  Hapus Semua Konfigurasi                        ║"
        echo "║   ${YELLOW}0.${CYAN}  Keluar                                       ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        
        read -p "Pilih opsi (0-4): " choice
        
        case $choice in
            1)
                echo -e "\n${BLUE}Memulai instalasi Panel...${NC}"
                check_root
                check_os
                update_system
                install_dependencies
                configure_database
                install_panel
                read -p "Press Enter to continue..."
                ;;
            2)
                echo -e "\n${BLUE}Memulai instalasi Wings...${NC}"
                check_root
                check_os
                update_system
                install_wings
                read -p "Press Enter to continue..."
                ;;
            3)
                echo -e "\n${BLUE}Memulai instalasi Panel + Wings...${NC}"
                check_root
                check_os
                update_system
                install_dependencies
                configure_database
                install_panel
                install_wings
                read -p "Press Enter to continue..."
                ;;
            4)
                uninstall_all
                read -p "Press Enter to continue..."
                ;;
            0)
                echo -e "\n${GREEN}Terima kasih telah menggunakan script installer!${NC}"
                exit 0
                ;;
            *)
                echo -e "\n${RED}Pilihan tidak valid!${NC}"
                sleep 2
                ;;
        esac
    done
}

# Fungsi utama
main() {
    # Cek jika ada parameter
    if [[ $# -gt 0 ]]; then
        case $1 in
            --panel)
                check_root
                check_os
                update_system
                install_dependencies
                configure_database
                install_panel
                ;;
            --wings)
                check_root
                check_os
                update_system
                install_wings
                ;;
            --uninstall)
                uninstall_all
                ;;
            --help)
                echo -e "${CYAN}Penggunaan:${NC}"
                echo "  ./install.sh              # Menu interaktif"
                echo "  ./install.sh --panel      # Install panel saja"
                echo "  ./install.sh --wings      # Install wings saja"
                echo "  ./install.sh --uninstall  # Hapus semua"
                echo "  ./install.sh --help       # Tampilkan bantuan"
                ;;
            *)
                echo -e "${RED}Parameter tidak dikenal!${NC}"
                echo "Gunakan --help untuk melihat opsi"
                exit 1
                ;;
        esac
    else
        # Jalankan menu interaktif
        show_menu
    fi
}

# Jalankan fungsi utama
main "$@"

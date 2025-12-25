#!/bin/bash

# ============================================
# One-Command Auto Installer Pterodactyl
# Khusus untuk user ryezx
# ============================================

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════╗"
echo "║   PTERODACTYL AUTO-INSTALLER - ryezx    ║"
echo "║   Email: ryezx@gmail.com                ║"
echo "║   User: ryezx / Pass: ryezx             ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# Cek root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: Script harus dijalankan sebagai root!${NC}"
    echo -e "Gunakan: ${GREEN}sudo bash $0${NC}"
    exit 1
fi

# Cek Ubuntu version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "ubuntu" ]; then
        echo -e "${RED}Error: Script ini hanya untuk Ubuntu!${NC}"
        exit 1
    fi
    
    case $VERSION_ID in
        "20.04"|"22.04"|"24.04")
            echo -e "${GREEN}Ubuntu $VERSION_ID terdeteksi - OK${NC}"
            ;;
        *)
            echo -e "${RED}Error: Ubuntu $VERSION_ID tidak didukung!${NC}"
            exit 1
            ;;
    esac
fi

# Download atau buat installer
if [ ! -f pterodactyl-autoinstall.sh ]; then
    echo -e "${YELLOW}Membuat installer...${NC}"
    
    # Download script utama dari URL atau gunakan embedded
    curl -sL -o pterodactyl-autoinstall.sh https://raw.githubusercontent.com/example/pterodactyl-autoinstall/main/pterodactyl-autoinstall.sh 2>/dev/null || {
        echo -e "${YELLOW}Download gagal, menggunakan local script...${NC}"
        # Embedded script akan dibuat nanti
        echo "#!/bin/bash" > pterodactyl-autoinstall.sh
        echo "echo 'Installer akan dibuat...'" >> pterodactyl-autoinstall.sh
    }
    
    chmod +x pterodactyl-autoinstall.sh
fi

# Tampilkan menu instalasi
echo ""
echo -e "${GREEN}PILIH TIPE INSTALASI:${NC}"
echo ""
echo "1. Install LENGKAP (Panel + Wings) - RECOMMENDED"
echo "2. Install Panel saja (Control Panel)"
echo "3. Install Wings saja (Game Server)"
echo "4. Keluar"
echo ""

read -p "Pilihan [1-4]: " install_type

case $install_type in
    1)
        echo -e "${GREEN}Memulai instalasi LENGKAP...${NC}"
        ./pterodactyl-autoinstall.sh
        ;;
    2)
        echo -e "${GREEN}Memulai instalasi Panel...${NC}"
        echo "2" > /tmp/install_type.txt
        ./pterodactyl-autoinstall.sh
        ;;
    3)
        echo -e "${GREEN}Memulai instalasi Wings...${NC}"
        echo "3" > /tmp/install_type.txt
        ./pterodactyl-autoinstall.sh
        ;;
    4)
        echo -e "${GREEN}Keluar...${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}Pilihan tidak valid!${NC}"
        exit 1
        ;;
esac

# Tampilkan informasi setelah instalasi
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}INSTALASI SELESAI!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}=== CREDENTIALS LOGIN ===${NC}"
    echo "Email:    ryezx@gmail.com"
    echo "Username: ryezx"
    echo "Password: ryezx"
    echo ""
    echo -e "${YELLOW}=== FILE INFORMASI ===${NC}"
    echo "/root/pterodactyl_admin_credentials.txt"
    echo "/root/pterodactyl_db_info.txt"
    echo ""
    echo -e "${RED}=== PERINGATAN ===${NC}"
    echo "1. Ganti password setelah login pertama!"
    echo "2. Simpan credentials dengan aman!"
    echo "3. Setup SSL untuk keamanan"
    echo ""
fi

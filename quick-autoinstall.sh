#!/bin/bash

# Quick Auto-Installer untuk Ryezx
# Hanya jalankan script ini dan ikuti petunjuk

echo "========================================"
echo "  Pterodactyl Auto-Installer - ryezx"
echo "========================================"
echo ""
echo "Konfigurasi otomatis akan digunakan:"
echo "Email: ryezx@gmail.com"
echo "Username: ryezx"
echo "Password: ryezx"
echo ""
echo "Anda hanya perlu memasukkan FQDN/domain"
echo ""

# Cek root
if [ "$EUID" -ne 0 ]; then 
    echo "Error: Jalankan dengan sudo!"
    echo "sudo bash $0"
    exit 1
fi

# Install dependencies
apt update
apt install -y curl wget

# Download installer utama
wget -O /tmp/ptero-auto.sh https://raw.githubusercontent.com/example/pterodactyl-autoinstall/main/pterodactyl-autoinstall.sh
chmod +x /tmp/ptero-auto.sh

# Jalankan installer
/tmp/ptero-auto.sh

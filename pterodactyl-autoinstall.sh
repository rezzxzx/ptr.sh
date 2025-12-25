#!/bin/bash

# Script: pterodactyl-auto-installer.sh
# Author: Auto-generated
# Description: Script otomatis install Wings Pterodactyl dengan konfigurasi otomatis

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
PANEL_URL=""
PANEL_TOKEN=""
NODE_NAME="AutoNode-$(date +%s)"
MEMORY_LIMIT="1024"
DISK_LIMIT="5120"
LOCATION_ID="1"

# Functions
print_header() {
    clear
    echo -e "${BLUE}"
    echo "=============================================="
    echo "    PTERODACTYL WINGS AUTO INSTALLER"
    echo "=============================================="
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}[✓] $1${NC}"
}

print_error() {
    echo -e "${RED}[✗] $1${NC}"
}

print_info() {
    echo -e "${YELLOW}[i] $1${NC}"
}

print_step() {
    echo -e "${BLUE}[→] $1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Script ini harus dijalankan sebagai root!"
        exit 1
    fi
}

# Check OS compatibility
check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        print_error "Tidak dapat mendeteksi sistem operasi!"
        exit 1
    fi
    
    print_info "Sistem Operasi: $OS $VER"
    
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" && "$OS" != "centos" && "$OS" != "rocky" && "$OS" != "almalinux" ]]; then
        print_error "Sistem operasi tidak didukung!"
        exit 1
    fi
}

# Get user input
get_input() {
    print_header
    echo -e "${YELLOW}Konfigurasi Otomatis Pterodactyl Wings${NC}"
    echo ""
    
    # Get FQDN
    while true; do
        read -p "Masukkan FQDN/domain untuk node ini (contoh: node.domain.com): " FQDN
        if [[ -n "$FQDN" ]]; then
            break
        else
            print_error "FQDN tidak boleh kosong!"
        fi
    done
    
    # Get Panel URL
    read -p "Masukkan URL Panel Pterodactyl [https://panel.domain.com]: " PANEL_URL
    if [[ -z "$PANEL_URL" ]]; then
        PANEL_URL="https://panel.domain.com"
    fi
    
    # Auto-generate email and username
    NODE_EMAIL="node_$(date +%s)@${FQDN#*.}"
    NODE_USERNAME="node_$(hostname)_$(date +%Y%m%d)"
    
    print_info "Email akan dibuat otomatis: $NODE_EMAIL"
    print_info "Username akan dibuat otomatis: $NODE_USERNAME"
    
    # Get configuration token
    while true; do
        echo ""
        print_info "Untuk mendapatkan Configuration Token:"
        print_info "1. Login ke panel Pterodactyl"
        print_info "2. Buka 'Configuration' > 'Nodes'"
        print_info "3. Klik node yang sudah dibuat atau buat baru"
        print_info "4. Scroll ke bawah, klik 'Generate Token'"
        echo ""
        read -p "Masukkan Configuration Token dari panel: " PANEL_TOKEN
        if [[ -n "$PANEL_TOKEN" && ${#PANEL_TOKEN} -gt 20 ]]; then
            break
        else
            print_error "Token tidak valid atau terlalu pendek!"
        fi
    done
    
    # Optional configurations
    read -p "Masukkan nama node [$NODE_NAME]: " input_node_name
    [[ -n "$input_node_name" ]] && NODE_NAME="$input_node_name"
    
    read -p "Masukkan memory limit (MB) [$MEMORY_LIMIT]: " input_memory
    [[ -n "$input_memory" ]] && MEMORY_LIMIT="$input_memory"
    
    read -p "Masukkan disk limit (MB) [$DISK_LIMIT]: " input_disk
    [[ -n "$input_disk" ]] && DISK_LIMIT="$input_disk"
    
    # Summary
    echo ""
    print_info "=== SUMMARY KONFIGURASI ==="
    echo "FQDN: $FQDN"
    echo "Panel URL: $PANEL_URL"
    echo "Node Name: $NODE_NAME"
    echo "Node Email: $NODE_EMAIL"
    echo "Node Username: $NODE_USERNAME"
    echo "Memory Limit: $MEMORY_LIMIT MB"
    echo "Disk Limit: $DISK_LIMIT MB"
    echo ""
    
    read -p "Lanjutkan installasi? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Installasi dibatalkan!"
        exit 0
    fi
}

# Install dependencies based on OS
install_dependencies() {
    print_step "Menginstall dependencies..."
    
    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y curl tar sqlite3
            ;;
        centos|rocky|almalinux)
            yum update -y
            yum install -y curl tar sqlite3
            ;;
    esac
    
    print_success "Dependencies terinstall!"
}

# Install Docker
install_docker() {
    print_step "Menginstall Docker..."
    
    if command -v docker &> /dev/null; then
        print_info "Docker sudah terinstall, melewati..."
        return
    fi
    
    curl -fsSL https://get.docker.com | bash
    systemctl enable --now docker
    
    print_success "Docker terinstall!"
}

# Install Wings
install_wings() {
    print_step "Menginstall Wings..."
    
    mkdir -p /etc/pterodactyl
    cd /etc/pterodactyl
    
    # Download wings
    curl -L -o /usr/local/bin/wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
    chmod u+x /usr/local/bin/wings
    
    # Create configuration directory
    mkdir -p /var/lib/pterodactyl /var/log/pterodactyl
    
    print_success "Wings terinstall!"
}

# Configure Wings
configure_wings() {
    print_step "Mengkonfigurasi Wings..."
    
    # Create wings configuration
    cat > /etc/pterodactyl/config.yml << EOF
debug: false
uuid: "$(cat /proc/sys/kernel/random/uuid)"
token: "$PANEL_TOKEN"
api:
  host: 0.0.0.0
  port: 8080
  ssl:
    enabled: false
    cert: /etc/letsencrypt/live/$FQDN/fullchain.pem
    key: /etc/letsencrypt/live/$FQDN/privkey.pem
  upload_limit: 100
system:
  data: /var/lib/pterodactyl
  sftp:
    bind_port: 2022
  username: $NODE_USERNAME
  user:
    uid: 998
    gid: 998
  detach_containers: false
allowed_mounts: []
remote: $PANEL_URL
container:
  docker:
    network:
      name: pterodactyl_nw
      network_interface: ""
    interfaces:
      - name: eth0
        type: internal
    dns:
      - 1.1.1.1
      - 1.0.0.1
    cpuset: []
    runtime: ""
  pid_limit: 512
  memory_limit: $MEMORY_LIMIT
  disk_limit: $DISK_LIMIT
  cpu_limit: 100
  threads: null
  oom_disabled: false
  privileged: false
  allocate: true
  image: "ghcr.io/pterodactyl/yolks:java_17"
  mounts: []
  log_configuration:
    type: json-file
    config:
      max-size: "50m"
      max-file: "3"
  security_opt: []
  extra_envs: []
  network_mode: bridge
  extra_hosts: []
  port_bindings: []
  labels: {}
EOF
    
    # Create systemd service
    cat > /etc/systemd/system/wings.service << EOF
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
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    # Create pterodactyl user
    if ! id -u pterodactyl >/dev/null 2>&1; then
        useradd -r -d /var/lib/pterodactyl -s /bin/false pterodactyl
        chown -R pterodactyl:pterodactyl /var/lib/pterodactyl
        chown -R pterodactyl:pterodactyl /var/log/pterodactyl
    fi
    
    # Set permissions
    chmod 750 /etc/pterodactyl
    chmod 640 /etc/pterodactyl/config.yml
    
    print_success "Konfigurasi Wings selesai!"
}

# Setup firewall
setup_firewall() {
    print_step "Mengatur firewall..."
    
    # Check if ufw is available
    if command -v ufw &> /dev/null; then
        ufw allow 22/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 8080/tcp
        ufw allow 2022/tcp
        ufw --force enable
        print_success "UFW dikonfigurasi!"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=22/tcp
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --permanent --add-port=443/tcp
        firewall-cmd --permanent --add-port=8080/tcp
        firewall-cmd --permanent --add-port=2022/tcp
        firewall-cmd --reload
        print_success "FirewallD dikonfigurasi!"
    else
        print_info "Firewall tidak terdeteksi, melewati..."
    fi
}

# Start wings service
start_wings() {
    print_step "Menjalankan Wings service..."
    
    systemctl daemon-reload
    systemctl enable --now wings
    
    # Check if service is running
    sleep 3
    if systemctl is-active --quiet wings; then
        print_success "Wings service berjalan!"
    else
        print_error "Wings service gagal berjalan!"
        journalctl -u wings --no-pager -n 20
        exit 1
    fi
}

# Generate SSL certificate (optional)
generate_ssl() {
    print_step "Membuat SSL certificate (self-signed)..."
    
    # Create directory for SSL
    mkdir -p /etc/letsencrypt/live/$FQDN
    
    # Generate self-signed certificate
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/letsencrypt/live/$FQDN/privkey.pem \
        -out /etc/letsencrypt/live/$FQDN/fullchain.pem \
        -subj "/C=ID/ST=Indonesia/L=Jakarta/O=Pterodactyl/CN=$FQDN" 2>/dev/null
    
    print_success "SSL certificate dibuat!"
}

# Show installation summary
show_summary() {
    print_header
    print_success "INSTALLASI SELESAI!"
    echo ""
    print_info "=== INFORMASI NODE ==="
    echo "FQDN: $FQDN"
    echo "Panel URL: $PANEL_URL"
    echo "Node Name: $NODE_NAME"
    echo "Wings Token: $PANEL_TOKEN"
    echo "SFTP Port: 2022"
    echo "Wings API Port: 8080"
    echo ""
    print_info "=== PERINTAH YANG BERGUNA ==="
    echo "• Status Wings: systemctl status wings"
    echo "• Restart Wings: systemctl restart wings"
    echo "• Log Wings: journalctl -u wings -f"
    echo "• Stop Wings: systemctl stop wings"
    echo ""
    print_info "=== UNTUK MENGHAPUS SEMUA KONFIGURASI ==="
    echo "Jalankan: ./pterodactyl-auto-installer.sh --uninstall"
    echo ""
}

# Uninstall everything
uninstall_all() {
    print_header
    echo -e "${RED}"
    echo "=============================================="
    echo "     UNINSTALL PTERODACTYL WINGS"
    echo "=============================================="
    echo -e "${NC}"
    
    read -p "Apakah Anda yakin ingin menghapus SEMUA konfigurasi Wings? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Uninstall dibatalkan!"
        exit 0
    fi
    
    print_step "Menghentikan dan menonaktifkan Wings service..."
    systemctl stop wings 2>/dev/null
    systemctl disable wings 2>/dev/null
    rm -f /etc/systemd/system/wings.service
    systemctl daemon-reload
    
    print_step "Menghapus Wings binary..."
    rm -f /usr/local/bin/wings
    
    print_step "Menghapus semua file konfigurasi..."
    rm -rf /etc/pterodactyl
    rm -rf /var/lib/pterodactyl
    rm -rf /var/log/pterodactyl
    rm -rf /var/run/wings
    
    print_step "Menghapus user pterodactyl..."
    if id -u pterodactyl >/dev/null 2>&1; then
        userdel pterodactyl 2>/dev/null
    fi
    
    print_step "Menghapus SSL certificates..."
    rm -rf /etc/letsencrypt/live/*$(hostname)* 2>/dev/null
    rm -rf /etc/letsencrypt/live/*$FQDN* 2>/dev/null
    
    # Optional: Uninstall docker (commented by default)
    # print_step "Menghapus Docker..."
    # if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    #     apt-get purge -y docker-ce docker-ce-cli containerd.io
    # elif [[ "$OS" == "centos" || "$OS" == "rocky" || "$OS" == "almalinux" ]]; then
    #     yum remove -y docker-ce docker-ce-cli containerd.io
    # fi
    # rm -rf /var/lib/docker
    
    print_success "Semua konfigurasi Wings telah dihapus!"
    echo ""
    print_info "Note: Docker masih terinstall. Jika ingin menghapus Docker juga, jalankan:"
    echo "• Ubuntu/Debian: apt-get purge docker-ce docker-ce-cli containerd.io"
    echo "• CentOS/Rocky: yum remove docker-ce docker-ce-cli containerd.io"
    echo ""
}

# Main installation function
main_install() {
    check_root
    check_os
    get_input
    install_dependencies
    install_docker
    install_wings
    generate_ssl
    configure_wings
    setup_firewall
    start_wings
    show_summary
}

# Main script logic
case "$1" in
    "--uninstall"|"-u")
        uninstall_all
        ;;
    "--help"|"-h")
        print_header
        echo "Penggunaan:"
        echo "  $0                    Install Wings Pterodactyl"
        echo "  $0 --uninstall        Hapus semua konfigurasi Wings"
        echo "  $0 --help             Tampilkan bantuan ini"
        echo ""
        echo "Fitur:"
        echo "  • Install Wings otomatis"
        echo "  • Konfigurasi otomatis dengan input FQDN saja"
        echo "  • Email dan username dibuat otomatis"
        echo "  • Generate SSL otomatis"
        echo "  • Uninstall lengkap"
        ;;
    *)
        main_install
        ;;
esac

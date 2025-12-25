#!/bin/bash

# Script untuk cek status instalasi Pterodactyl

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════╗"
echo "║   PTERODACTYL INSTALLATION CHECKER      ║"
echo "║   User: ryezx / Pass: ryezx             ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# Cek services
echo -e "${YELLOW}=== STATUS SERVICES ===${NC}"
echo ""

services=("nginx" "mariadb" "php8.1-fpm" "php8.3-fpm" "wings" "redis-server")
for service in "${services[@]}"; do
    if systemctl is-active --quiet $service 2>/dev/null; then
        echo -e "${GREEN}✓ $service is RUNNING${NC}"
    else
        echo -e "${RED}✗ $service is NOT RUNNING${NC}"
    fi
done

echo ""
echo -e "${YELLOW}=== CHECKING PORTS ===${NC}"
echo ""

ports=("80" "443" "3306" "2022" "8080")
for port in "${ports[@]}"; do
    if netstat -tulpn | grep ":$port " > /dev/null; then
        echo -e "${GREEN}✓ Port $port is OPEN${NC}"
    else
        echo -e "${RED}✗ Port $port is CLOSED${NC}"
    fi
done

echo ""
echo -e "${YELLOW}=== CHECKING FILES ===${NC}"
echo ""

files=("/var/www/pterodactyl/.env" "/etc/pterodactyl/config.yml" "/root/pterodactyl_admin_credentials.txt")
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓ $file exists${NC}"
    else
        echo -e "${RED}✗ $file missing${NC}"
    fi
done

echo ""
echo -e "${YELLOW}=== DATABASE CHECK ===${NC}"
echo ""

if mysql -e "USE panel;" 2>/dev/null; then
    echo -e "${GREEN}✓ Database 'panel' exists${NC}"
    
    # Cek tables
    table_count=$(mysql -e "USE panel; SHOW TABLES;" 2>/dev/null | wc -l)
    echo -e "${GREEN}✓ Found $table_count tables in database${NC}"
else
    echo -e "${RED}✗ Database 'panel' not found${NC}"
fi

echo ""
echo -e "${YELLOW}=== LOGIN INFORMATION ===${NC}"
echo ""

if [ -f "/root/pterodactyl_admin_credentials.txt" ]; then
    grep -E "(Email|Username|Password|Panel URL)" /root/pterodactyl_admin_credentials.txt | head -5
else
    echo -e "${RED}Credentials file not found${NC}"
    echo -e "${YELLOW}Default credentials:${NC}"
    echo "Email: ryezx@gmail.com"
    echo "Username: ryezx"
    echo "Password: ryezx"
fi

echo ""
echo -e "${YELLOW}=== RECOMMENDED ACTIONS ===${NC}"
echo "1. Change default password after first login"
echo "2. Setup SSL certificate"
echo "3. Configure backup schedule"
echo "4. Update firewall rules for game ports"
echo ""

# Tampilkan panel URL jika tersedia
if [ -f "/var/www/pterodactyl/.env" ]; then
    PANEL_URL=$(grep "APP_URL=" /var/www/pterodactyl/.env | cut -d'=' -f2)
    echo -e "${GREEN}Panel URL: $PANEL_URL${NC}"
fi

#!/usr/bin/env bash
set -euo pipefail

# =========================
# Pterodactyl Panel Auto Installer (Ubuntu 20/22/24)
# Only asks: FQDN
# Fixed creds:
#   SSL email   : ryezx@gmail.com
#   Admin email : ryezx@gmail.com
#   Admin user  : ryezx
#   Admin pass  : ryezx
# Timezone: Asia/Jakarta
# =========================

### --- CONFIG (edit if you want)
TZ_DEFAULT="Asia/Jakarta"
PANEL_DIR="/var/www/pterodactyl"
WEB_USER="www-data"

SSL_EMAIL="ryezx@gmail.com"
ADMIN_EMAIL="ryezx@gmail.com"
ADMIN_USER="ryezx"
ADMIN_PASS="ryezx"

# If you want install Wings too on same server:
INSTALL_WINGS="no"  # change to "yes" if needed

### --- Pretty output
GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; BLUE="\033[0;34m"; NC="\033[0m"
STEP=0
TOTAL_STEPS=13

say() { echo -e "${BLUE}==>${NC} $*"; }
ok()  { echo -e "${GREEN}[OK]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
die() { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

progress() {
  STEP=$((STEP+1))
  local pct=$(( STEP * 100 / TOTAL_STEPS ))
  echo -e "${GREEN}-- Step ${STEP}/${TOTAL_STEPS} (${pct}%) --${NC} $*"
}

need_root() {
  [[ "${EUID}" -eq 0 ]] || die "Jalankan sebagai root. (pakai: sudo bash ptr.sh)"
}

detect_ubuntu() {
  [[ -f /etc/os-release ]] || die "Gagal deteksi OS."
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID}" == "ubuntu" ]] || die "Script ini khusus Ubuntu. OS lu: ${ID}"
  case "${VERSION_ID}" in
    "20.04"|"22.04"|"24.04") ok "Ubuntu ${VERSION_ID} terdeteksi." ;;
    *) die "Ubuntu ${VERSION_ID} belum disupport. (Cuma 20.04/22.04/24.04)" ;;
  esac
}

rand_pw() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32; }

get_latest_panel_tag() {
  # fallback tag kalau GitHub API rate limit / fail
  local tag="v1.11.11"
  if command -v curl >/dev/null 2>&1; then
    local api="https://api.github.com/repos/pterodactyl/panel/releases/latest"
    local got
    got="$(curl -fsSL "$api" | grep -m1 '"tag_name"' | cut -d '"' -f4 || true)"
    [[ -n "${got}" ]] && tag="${got}"
  fi
  echo "${tag}"
}

trap 'die "Script stop di line $LINENO. Coba jalankan: sudo bash -x ptr.sh untuk debug."' ERR

# ---- Start
need_root
progress "Cek OS & versi"
detect_ubuntu

echo
read -rp "Masukin FQDN panel (contoh: panel.domainlu.com): " FQDN
[[ -n "${FQDN}" ]] || die "FQDN gak boleh kosong."

# ---- DB creds auto
DB_NAME="pterodactyl"
DB_USER="ptero"
DB_PASS="$(rand_pw)"

progress "Set timezone → ${TZ_DEFAULT}"
timedatectl set-timezone "${TZ_DEFAULT}" || true

progress "Update apt + install dependency dasar"
apt-get update -y
apt-get install -y software-properties-common curl wget ca-certificates gnupg lsb-release unzip tar git ufw

progress "Install MariaDB + Redis + Nginx + Certbot"
apt-get install -y mariadb-server redis-server nginx certbot python3-certbot-nginx

progress "Install PHP 8.3 (PPA ondrej) + extensions"
add-apt-repository -y ppa:ondrej/php
apt-get update -y
apt-get install -y \
  php8.3 php8.3-cli php8.3-fpm php8.3-mysql php8.3-redis php8.3-gd php8.3-mbstring \
  php8.3-xml php8.3-curl php8.3-zip php8.3-bcmath php8.3-intl

progress "Install Composer v2"
if ! command -v composer >/dev/null 2>&1; then
  curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
fi
ok "Composer ready"

progress "Setup database (db + user + password random)"
mysql -u root <<MYSQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL

progress "Download Panel release terbaru + extract"
mkdir -p "${PANEL_DIR}"
cd "${PANEL_DIR}"
TAG="$(get_latest_panel_tag)"
ok "Panel tag: ${TAG}"
curl -fsSL -o panel.tar.gz "https://github.com/pterodactyl/panel/releases/download/${TAG}/panel.tar.gz"
tar -xzf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

progress "Composer install + generate app key"
export COMPOSER_ALLOW_SUPERUSER=1
composer install --no-dev --optimize-autoloader
php artisan key:generate --force

progress "Setup environment + database + migrate + seed (AUTO)"
php artisan p:environment:setup -n \
  --author="${ADMIN_EMAIL}" \
  --url="https://${FQDN}" \
  --timezone="${TZ_DEFAULT}" \
  --cache="redis" \
  --session="database" \
  --queue="redis"

php artisan p:environment:database -n \
  --host="127.0.0.1" \
  --port="3306" \
  --database="${DB_NAME}" \
  --username="${DB_USER}" \
  --password="${DB_PASS}"

php artisan migrate --seed --force

progress "Buat admin user (AUTO)"
php artisan p:user:make -n \
  --email="${ADMIN_EMAIL}" \
  --username="${ADMIN_USER}" \
  --name="Administrator" \
  --password="${ADMIN_PASS}" \
  --admin=1

progress "Permission + queue worker service"
chown -R ${WEB_USER}:${WEB_USER} "${PANEL_DIR}"

cat >/etc/systemd/system/pteroq.service <<'SERVICE'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --sleep=3 --tries=3 --timeout=120

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now pteroq

progress "Config Nginx site"
cat >/etc/nginx/sites-available/pterodactyl.conf <<NGINX
server {
    listen 80;
    server_name ${FQDN};

    root ${PANEL_DIR}/public;
    index index.php;

    client_max_body_size 100m;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
rm -f /etc/nginx/sites-enabled/default || true
nginx -t
systemctl reload nginx

progress "Firewall 80/443 + SSL cert"
ufw allow 80/tcp || true
ufw allow 443/tcp || true

# SSL - will fail if DNS A record belum bener
certbot --nginx -d "${FQDN}" --non-interactive --agree-tos -m "${SSL_EMAIL}" --redirect || warn "Certbot gagal (cek DNS A record FQDN → IP VPS, dan port 80/443 kebuka)."

if [[ "${INSTALL_WINGS}" == "yes" ]]; then
  progress "Install Wings (Docker + wings binary)"
  apt-get install -y docker.io
  systemctl enable --now docker

  mkdir -p /etc/pterodactyl
  ARCH="$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
  curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH}"
  chmod u+x /usr/local/bin/wings

  cat >/etc/systemd/system/wings.service <<'WINGS'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
ExecStart=/usr/local/bin/wings
Restart=on-failure

[Install]
WantedBy=multi-user.target
WINGS

  systemctl daemon-reload
  systemctl enable wings
  warn "Wings butuh config.yml dari Panel → Nodes → Configuration"
fi

echo
echo -e "${GREEN}================= DONE =================${NC}"
echo "URL panel : https://${FQDN}"
echo "Timezone  : ${TZ_DEFAULT}"
echo
echo -e "${YELLOW}Admin Panel (AUTO)${NC}"
echo "Email     : ${ADMIN_EMAIL}"
echo "Username  : ${ADMIN_USER}"
echo "Password  : ${ADMIN_PASS}"
echo
echo -e "${YELLOW}DB (AUTO, SIMPEN)${NC}"
echo "DB name   : ${DB_NAME}"
echo "DB user   : ${DB_USER}"
echo "DB pass   : ${DB_PASS}"
echo -e "${GREEN}========================================${NC}"

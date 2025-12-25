#!/usr/bin/env bash
set -Eeuo pipefail

TZ_DEFAULT="Asia/Jakarta"
PANEL_DIR="/var/www/pterodactyl"
WEB_USER="www-data"

SSL_EMAIL="ryezx@gmail.com"
ADMIN_EMAIL="ryezx@gmail.com"
ADMIN_USER="ryezx"
ADMIN_PASS="ryezx"

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; BLUE="\033[0;34m"; NC="\033[0m"
STEP=0
TOTAL_STEPS=12

say(){ echo -e "${BLUE}==>${NC} $*"; }
ok(){ echo -e "${GREEN}[OK]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
err(){ echo -e "${RED}[ERR]${NC} $*"; }

progress(){
  STEP=$((STEP+1))
  local pct=$(( STEP * 100 / TOTAL_STEPS ))
  echo -e "${GREEN}-- Step ${STEP}/${TOTAL_STEPS} (${pct}%) --${NC} $*"
}

need_root(){
  [[ "${EUID}" -eq 0 ]] || { err "Run as root: sudo bash ptr.sh"; exit 1; }
}

detect_ubuntu(){
  . /etc/os-release
  [[ "${ID}" == "ubuntu" ]] || { err "OS bukan Ubuntu: ${ID}"; exit 1; }
  case "${VERSION_ID}" in
    "20.04"|"22.04"|"24.04") ok "Ubuntu ${VERSION_ID} terdeteksi." ;;
    *) err "Ubuntu ${VERSION_ID} tidak disupport."; exit 1 ;;
  esac
}

rand_pw(){ tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32; }

get_latest_panel_tag(){
  local fallback="v1.11.11"
  local tag="${fallback}"
  if command -v curl >/dev/null 2>&1; then
    local got
    got="$(curl -fsSL https://api.github.com/repos/pterodactyl/panel/releases/latest \
      | grep -m1 '"tag_name"' | cut -d '"' -f4 || true)"
    [[ -n "${got}" ]] && tag="${got}"
  fi
  echo "${tag}"
}

# Print the failing command + line if something blows up
on_fail(){
  local code=$?
  err "Gagal di line ${BASH_LINENO[0]}: ${BASH_COMMAND}"
  err "Exit code: ${code}"
  exit "${code}"
}
trap on_fail ERR

need_root
progress "Cek OS"
detect_ubuntu

echo
read -rp "Masukin FQDN panel (contoh: panel.domainlu.com): " FQDN
[[ -n "${FQDN}" ]] || { err "FQDN kosong."; exit 1; }

DB_NAME="pterodactyl"
DB_USER="ptero"
DB_PASS="$(rand_pw)"

progress "Set timezone → ${TZ_DEFAULT}"
timedatectl set-timezone "${TZ_DEFAULT}" || true

progress "Update apt + install deps"
apt-get update -y
apt-get install -y curl wget ca-certificates gnupg unzip tar git ufw software-properties-common

progress "Install MariaDB + Redis + Nginx + Certbot"
apt-get install -y mariadb-server redis-server nginx certbot python3-certbot-nginx

progress "Install PHP (repo bawaan Ubuntu) + extensions"
apt-get install -y \
  php php-cli php-fpm php-mysql php-redis php-gd php-mbstring \
  php-xml php-curl php-zip php-bcmath php-intl

progress "Install Composer"
if ! command -v composer >/dev/null 2>&1; then
  curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
fi
ok "Composer: $(composer --version | head -n1)"

progress "Setup DB"
mysql -u root <<MYSQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL

progress "Download & extract Panel"
mkdir -p "${PANEL_DIR}"
cd "${PANEL_DIR}"
TAG="$(get_latest_panel_tag)"
ok "Panel tag: ${TAG}"
curl -fsSL -o panel.tar.gz "https://github.com/pterodactyl/panel/releases/download/${TAG}/panel.tar.gz"
tar -xzf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

progress "Composer install + app key"
export COMPOSER_ALLOW_SUPERUSER=1
composer install --no-dev --optimize-autoloader
php artisan key:generate --force

progress "Configure environment + DB + migrate"
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

progress "Create admin user"
php artisan p:user:make -n \
  --email="${ADMIN_EMAIL}" \
  --username="${ADMIN_USER}" \
  --name="Administrator" \
  --password="${ADMIN_PASS}" \
  --admin=1

progress "Permissions + queue worker"
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

progress "Nginx config"
PHP_SOCK="$(php -r 'echo "unix:/run/php/php".PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION."-fpm.sock";')"

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
    fastcgi_pass ${PHP_SOCK};
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

progress "Firewall + SSL"
ufw allow 80/tcp || true
ufw allow 443/tcp || true

certbot --nginx -d "${FQDN}" --non-interactive --agree-tos -m "${SSL_EMAIL}" --redirect || warn "Certbot gagal: pastiin DNS A record FQDN udah ke IP VPS & port 80/443 kebuka."

echo
ok "DONE"
echo "Panel URL : https://${FQDN}"
echo "Admin     : ${ADMIN_USER} / ${ADMIN_PASS} (${ADMIN_EMAIL})"
echo "DB pass   : ${DB_PASS}  (SIMPEN!)"

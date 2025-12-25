#!/usr/bin/env bash
set -euo pipefail

# ---------- Simple progress (by steps) ----------
TOTAL_STEPS=18
STEP=0
progress() {
  STEP=$((STEP + 1))
  local pct=$((STEP * 100 / TOTAL_STEPS))
  echo ""
  echo "========== [${pct}%] $1 =========="
}
run() {
  # run "description" command...
  local msg="$1"; shift
  progress "$msg"
  "$@"
}

# ---------- Root check ----------
if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

# ---------- Detect Ubuntu version ----------
if ! command -v lsb_release >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y lsb-release
fi

DISTRO="$(lsb_release -is)"
VER="$(lsb_release -rs)"

if [[ "$DISTRO" != "Ubuntu" ]]; then
  echo "This script supports Ubuntu only. Detected: $DISTRO"
  exit 1
fi

if [[ "$VER" != "24.04" && "$VER" != "22.04" && "$VER" != "20.04" ]]; then
  echo "Supported Ubuntu: 20.04 / 22.04 / 24.04. Detected: $VER"
  exit 1
fi

PHP_VERSION="8.2"
if [[ "$VER" == "24.04" ]]; then
  PHP_VERSION="8.3"
fi

TIMEZONE="Asia/Jakarta"

echo "=== Pterodactyl Panel Installer (Ubuntu $VER) ==="
echo "PHP selected: $PHP_VERSION"
echo "Timezone    : $TIMEZONE"
echo ""

# ---------- Inputs ----------
read -rp "Panel domain (example: panel.example.com): " PTERO_DOMAIN
read -rp "Email for Let's Encrypt SSL: " LE_EMAIL

echo ""
echo "=== Create FIRST Admin Account ==="
read -rp "Admin email: " ADMIN_EMAIL
read -rp "Admin username: " ADMIN_USER
read -rp "First name (default: Admin): " ADMIN_FN
ADMIN_FN="${ADMIN_FN:-Admin}"
read -rp "Last name (default: User): " ADMIN_LN
ADMIN_LN="${ADMIN_LN:-User}"

# Hidden password input
while true; do
  read -rsp "Admin password: " ADMIN_PASS; echo ""
  read -rsp "Confirm password: " ADMIN_PASS2; echo ""
  [[ "$ADMIN_PASS" == "$ADMIN_PASS2" ]] && break
  echo "Passwords don't match. Try again."
done

DB_PASS="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)"

echo ""
echo "Domain : $PTERO_DOMAIN"
echo "SSL    : $LE_EMAIL"
echo "Admin  : $ADMIN_EMAIL / $ADMIN_USER"
echo ""

# ---------- Steps ----------
run "Updating system packages" apt-get update -y
run "Upgrading system" apt-get upgrade -y

run "Installing base packages" apt-get install -y curl wget git unzip tar ca-certificates gnupg ufw software-properties-common

run "Setting timezone (Asia/Jakarta)" timedatectl set-timezone "$TIMEZONE"

run "Installing MariaDB + Redis" apt-get install -y mariadb-server redis-server
run "Installing Nginx" apt-get install -y nginx

run "Adding PHP PPA (ondrej) + installing PHP ${PHP_VERSION}" bash -lc "
  add-apt-repository -y ppa:ondrej/php &&
  apt-get update -y &&
  apt-get install -y \
    php${PHP_VERSION} php${PHP_VERSION}-cli php${PHP_VERSION}-fpm php${PHP_VERSION}-common \
    php${PHP_VERSION}-mysql php${PHP_VERSION}-zip php${PHP_VERSION}-gd php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-curl php${PHP_VERSION}-xml php${PHP_VERSION}-bcmath php${PHP_VERSION}-intl
"

run "Installing Composer" bash -lc '
  if ! command -v composer >/dev/null 2>&1; then
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
  fi
'

run "Creating database + db user" bash -lc "
  mysql -u root <<MYSQL
CREATE DATABASE IF NOT EXISTS panel;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL
"

run "Downloading Pterodactyl Panel" bash -lc "
  mkdir -p /var/www/pterodactyl &&
  cd /var/www/pterodactyl &&
  curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz &&
  tar -xzf panel.tar.gz &&
  chmod -R 755 storage/* bootstrap/cache/
"

run "Installing panel dependencies (composer)" bash -lc "
  cd /var/www/pterodactyl &&
  cp -n .env.example .env &&
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
"

run "Generating APP_KEY" bash -lc "
  cd /var/www/pterodactyl &&
  php artisan key:generate --force
"

run "Configuring environment (redis + db)" bash -lc "
  cd /var/www/pterodactyl &&
  php artisan p:environment:setup \
    --author='${LE_EMAIL}' \
    --url='https://${PTERO_DOMAIN}' \
    --timezone='${TIMEZONE}' \
    --cache=redis \
    --session=redis \
    --queue=redis \
    --redis-host=127.0.0.1 \
    --redis-pass='' \
    --redis-port=6379 &&
  php artisan p:environment:database \
    --host=127.0.0.1 \
    --port=3306 \
    --database=panel \
    --username=pterodactyl \
    --password='${DB_PASS}'
"

run "Running migrations (seed database)" bash -lc "
  cd /var/www/pterodactyl &&
  php artisan migrate --seed --force
"

run "Setting permissions" bash -lc "
  chown -R www-data:www-data /var/www/pterodactyl/*
"

run "Creating first admin user (non-interactive)" bash -lc "
  cd /var/www/pterodactyl &&
  php artisan p:user:make \
    --email='${ADMIN_EMAIL}' \
    --username='${ADMIN_USER}' \
    --name-first='${ADMIN_FN}' \
    --name-last='${ADMIN_LN}' \
    --password='${ADMIN_PASS}' \
    --admin=1 \
    --no-interaction
"

run "Setting up cron + queue worker service" bash -lc "
  ( crontab -l 2>/dev/null | grep -v 'pterodactyl' || true
    echo \"* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1 # pterodactyl\"
  ) | crontab -

  cat >/etc/systemd/system/pteroq.service <<'SERVICE'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --sleep=3 --tries=3 --max-time=3600
StartLimitInterval=180
StartLimitBurst=30

[Install]
WantedBy=multi-user.target
SERVICE

  systemctl daemon-reload
  systemctl enable --now pteroq
"

run "Configuring Nginx vhost" bash -lc "
  cat >/etc/nginx/sites-available/pterodactyl.conf <<NGINX
server {
  listen 80;
  server_name ${PTERO_DOMAIN};

  root /var/www/pterodactyl/public;
  index index.php;

  client_max_body_size 100m;

  location / {
    try_files \\\$uri \\\$uri/ /index.php?\\\$query_string;
  }

  location ~ \\\\.php\\\$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
  }

  location ~ /\\\\.ht {
    deny all;
  }
}
NGINX

  ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl restart nginx
  systemctl enable nginx
"

run "Installing SSL (Certbot) + redirect HTTPS" bash -lc "
  apt-get install -y certbot python3-certbot-nginx &&
  certbot --nginx -d '${PTERO_DOMAIN}' -m '${LE_EMAIL}' --agree-tos --no-eff-email --redirect
"

run "Firewall (UFW) OpenSSH + Nginx Full" bash -lc "
  ufw allow OpenSSH
  ufw allow 'Nginx Full'
  ufw --force enable
"

echo ""
echo "✅ DONE! Panel installed."
echo "URL     : https://${PTERO_DOMAIN}"
echo "Admin   : ${ADMIN_EMAIL} (username: ${ADMIN_USER})"
echo "DB user : pterodactyl"
echo "DB pass : ${DB_PASS}"
echo ""
echo "Next: install Wings on node (separate step)."

#!/bin/bash
set -e

# === Update system ===
apt update
apt upgrade -y
apt install -y curl wget gnupg2 ca-certificates lsb-release ubuntu-keyring

# === 安裝網站 AP 必要套件 ===
# Install MySQL client
apt install -y mysql-client-8.0

# Install Apache2
apt install -y apache2

# Install PHP core and database extension
apt install -y \
  php \
  php-mysql

# Install PHP extensions for WordPress
apt install -y \
  php-curl \
  php-gd \
  php-xml \
  php-xmlrpc \
  php-soap \
  php-json \
  php-zip

# Enable Apache modules
a2enmod rewrite
a2enmod ssl

# === 安裝並設置 WordPress ===
# Download and configure WordPress
cd /var/www/html
rm -f index.html
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
mv wordpress/* .
rmdir wordpress
rm latest.tar.gz

# Set proper permissions
chown -R www-data:www-data /var/www/html # www-data 是 Apache 的預設使用者
chmod -R 755 /var/www/html 

# Create WordPress `wp-config.php`（包含 DB 連線相關資訊）
# WordPress 官方 salt key 產生器：https://api.wordpress.org/secret-key/1.1/salt/
cat > /var/www/html/wp-config.php << 'WPEOF' 
<?php
define('DB_NAME', '${db_name}');
define('DB_USER', '${db_user}');
define('DB_PASSWORD', '${db_password}');
define('DB_HOST', '${db_host}');
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');

define('AUTH_KEY',         'iB_1:=l1p(Pc*Od1<_]^ST$3VCAxUD +X{)}{(TJ.n&8UgkVPdtlB@LzhS:ob+-3');
define('SECURE_AUTH_KEY',  'O,fMfj?yX:v&,^vY|rIJ|U1H.ZNMYfBpF|0Sx^oxT`m{ Rr?R|G*[_H>FWL_#bu:');
define('LOGGED_IN_KEY',    'xMHduB{K%~w4`.Y-mzKjeD<2v-9h/Am;2o-;pe|4wkPo,U6R:P+7y>+jvb|U3weo');
define('NONCE_KEY',        'YKe&&g6 OlP)A[`SeO|G{lK1{p-5]TPX|`b@C-I+Kl@:;;?pl{,._:|crSF@Ad8v');
define('AUTH_SALT',        'Mu.jrVG%RHjn!-6G;!p];ILea]Uvt!0b>Y|_N-S0JrK7;5l;8/T|#]BlF%-[cN!X');
define('SECURE_AUTH_SALT', '^I2_z`FX`OxTT{8.J9Q|]U)5n%i6|?aIdCr[JIg7x)}uik.Cn`T!m+LHWg7wYTQ`');
define('LOGGED_IN_SALT',   'tr$@-/33|lpT*/q@>Xf0j0ZT$2U/QMeBvTl&OxP1q!]=Zg]K|e)JWMvMe.6)|/7X');
define('NONCE_SALT',       '.32M;hlz@3E97(NG-^h&)IRo|M^??:zD.?+v!1I>/yL?yw9W[_FNsLe&r}ra4]i:');

$table_prefix = 'wp_';

define('WP_DEBUG', false);

if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
?>
WPEOF

# === 等待 RDS 可用，並建立 WordPress 資料庫使用者 ===
# Wait for RDS to be available
echo "Waiting for RDS to be available..."
until mysql -h "${db_host}" -u master -p"${db_master_password}" -e "SELECT 1" > /dev/null 2>&1; do
  echo "Retrying database connection..."
  sleep 10
done

# Create WordPress user
mysql -h "${db_host}" -u master -p"${db_master_password}" << MYSQLEOF
CREATE USER IF NOT EXISTS '${db_user}'@'10.0.%.%' IDENTIFIED BY '${db_password}';
GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'10.0.%.%';
FLUSH PRIVILEGES;
MYSQLEOF

# === 重啟 web 服務 ===
# Restart Apache
systemctl restart apache2

echo "WordPress setup complete!"

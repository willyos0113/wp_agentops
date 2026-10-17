#!/bin/bash
# === 執行流程（EC2 第一次開機時以 root 執行一次，由上往下依序進行）===
# [ Terraform templatefile ] (送到 EC2 之前，先把變數佔位符換成實際值，見 compute.tf)
#        │
#        ▼
# [ 更新系統 ] (apt update / upgrade)
#        │
#        ▼
# [ 安裝 Apache、PHP、MySQL client ] ──► (啟用 rewrite，允許 .htaccess 生效)
#        │
#        ▼
# [ 下載 WordPress ] ──► (解壓到 /var/www/html，擁有者改為 www-data)
#        │
#        ▼
# [ 寫出 wp-config.php ] (WordPress 連 DB 用的資訊)
#        │
#        ▼ (每 10 秒重試，直到 RDS 連得上)
# [ 建立 WordPress 的 DB 使用者 ] (用 master 帳號登入 RDS 建立)
#        │
#        ▼
# [ 重啟 Apache ] ──► (WordPress 上線)
#        │
#        ▼
# [ 安裝 CloudWatch Agent ]
#        │
#        ▼ (寫出設定檔：要讀哪些 log 檔、送到哪個 log group)
# [ 啟動 CloudWatch Agent ] ──► (Apache 日誌開始送往 CloudWatch Logs)

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
# 將 /var/www/ 的 AllowOverride None 改為 AllowOverride All，允許 .htaccess 生效
# (解決 WordPress 後台連結無法正常跳轉的問題)
sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf

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
define('DB_HOST', '${db_host}:3306');
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

// 網站網址固定為 HTTPS 網域；TLS 在 ALB 終止，EC2 收到的是 HTTP，
// 因此要信任 ALB 帶來的 X-Forwarded-Proto，否則 WordPress 會判成 HTTP 而無限轉導
define('WP_HOME', 'https://${domain_name}');
define('WP_SITEURL', 'https://${domain_name}');
if ( isset( $_SERVER['HTTP_X_FORWARDED_PROTO'] ) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) {
	$_SERVER['HTTPS'] = 'on';
}

// 開啟除錯但不顯示在頁面上：連不上 DB 等錯誤會寫進 Apache error log，供 CloudWatch investigations 判讀
define('WP_DEBUG', true);
define('WP_DEBUG_DISPLAY', false);

if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
?>
WPEOF

# === 等待 RDS 可用，並建立 WordPress 資料庫使用者 ===
# Wait for RDS to be available
echo "Waiting for RDS to be available..."
until mysql -h "${db_host}" -P 3306 -u master -p"${db_master_password}" -e "SELECT 1" > /dev/null 2>&1; do
  echo "Retrying database connection..."
  sleep 10
done

# Create WordPress user
mysql -h "${db_host}" -P 3306 -u master -p"${db_master_password}" << MYSQLEOF
CREATE USER IF NOT EXISTS '${db_user}'@'10.0.%' IDENTIFIED BY '${db_password}';
GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'10.0.%';
FLUSH PRIVILEGES;
MYSQLEOF

# === 重啟 web 服務 ===
# Restart Apache
systemctl restart apache2

echo "WordPress setup complete!"

# === 安裝並設置 CloudWatch Agent（將 Apache 日誌送進 CloudWatch Logs）===
# Download and install the CloudWatch Agent
# note: after installation, the deb file will be removed to save disk space
wget -q https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /tmp/amazon-cloudwatch-agent.deb
dpkg -i -E /tmp/amazon-cloudwatch-agent.deb
rm /tmp/amazon-cloudwatch-agent.deb

# Create CloudWatch Agent configuration file
# note1: `{instance_id}` will be replaced by the CloudWatch Agent
# note2: `${access_log_group}` and `${error_log_group}` will be replaced by Terraform
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWEOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/apache2/access.log",
            "log_group_name": "${access_log_group}",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/apache2/error.log",
            "log_group_name": "${error_log_group}",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
CWEOF

# Start the CloudWatch Agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

echo "CloudWatch Agent setup complete!"

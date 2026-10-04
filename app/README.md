# WordPress 應用層

此目錄用於存放 WordPress 應用相關的配置和自定義。

## 結構

```
app/
├── plugins/          # WordPress 插件（可選）
├── themes/           # 自定義主題（可選）
├── wp-config/        # WordPress 配置片段（可選）
└── README.md         # 本檔案
```

## 說明

當前 WordPress 通過以下方式部署：

1. **自動部署**: 通過 `infra/user_data.sh` 在 EC2 啟動時自動安裝
2. **資料庫配置**: 通過 Terraform 變數自動配置資料庫連接
3. **WordPress 用戶**: 通過 MySQL 腳本自動建立

## 自定義 WordPress

如要自定義 WordPress 部署，可以：

### 1. 修改 user_data.sh
編輯 `infra/user_data.sh` 添加：
- 額外的 PHP 擴展
- WordPress 插件的自動安裝
- 主題配置
- 安全設定

### 2. 添加插件
將插件放在 `app/plugins/` 目錄中，然後在 `user_data.sh` 中添加複製命令：

```bash
cp -r /tmp/app/plugins/* /var/www/html/wp-content/plugins/
```

### 3. 自定義配置
在此目錄中存放任何需要版本控制的 WordPress 配置檔案。

## 部署流程

1. **Terraform 啟動 EC2 實例** — 在公開子網建立
2. **執行 user_data.sh 腳本** — 自動化部署流程
   ```bash
   ├─ 系統更新（apt update/upgrade）
   ├─ 安裝 Apache2（Web Server）
   ├─ 安裝 PHP 核心和擴展
   ├─ 安裝 MySQL 客戶端
   ├─ 啟用 Apache 模組（rewrite、ssl）
   ├─ 下載並解壓 WordPress
   ├─ 設置檔案權限（www-data）
   ├─ 生成 wp-config.php（含 Salt Key）
   ├─ 等待 RDS 就緒
   ├─ 建立 WordPress 資料庫用戶（wp@10.0.%.%）
   └─ 啟動 Apache
   ```

## 訪問 WordPress

部署完成後，有兩種方式訪問：

### 方式 A: 直接訪問公網 IP
```bash
# 使用 Terraform output 中的 WordPress URL
http://<ec2_public_ip>

# 或手動拼接
curl -I http://<ec2_public_ip>
```

### 方式 B: 使用 SSH 連接進行維護
```bash
# 傳統 SSH 方式
ssh -i infra/yiweee.pem ubuntu@<ec2_public_ip>

# 或使用 SSM Session Manager（推薦）
aws ssm start-session --target <instance-id> --region ap-northeast-1
```

## WordPress 初始設置

首次訪問會重定向到 WordPress 安裝嚮導：

1. 選擇語言
2. 建立管理員帳號
3. 完成初始配置
4. 開始發佈內容

## 連接資料庫

若需直接連接 MySQL：

```bash
# 在 EC2 上執行
mysql -h <rds_endpoint> -u wp -p<db_wp_password> wordpress

# 查詢文章
SELECT post_title, post_date FROM wp_posts WHERE post_type='post';
```

## 架構特性

- ✅ **自動化部署** — user_data.sh 完全自動化
- ✅ **安全隔離** — RDS 在私有子網，只允許 EC2 連接
- ✅ **Salt Key 隨機化** — 8 個 WordPress 密鑰已隨機生成
- ✅ **跨 AZ 準備** — 支持未來 RDS Multi-AZ 升級
- ✅ **版本一致** — Ubuntu 22.04 LTS、Apache2、PHP 8+、MySQL 8.0


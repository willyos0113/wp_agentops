# 部署指南

本文件說明如何部署 WordPress Web/DB 分層架構到 AWS。

## 前置條件

1. **AWS 帳戶** - 已配置 AWS CLI 且具有適當的 IAM 權限
2. **Terraform** - 版本 >= 1.0
3. **公網 IP** - 用於 SSH 維護存取（自己的外部 IP），或使用 SSM Session Manager 替代
4. **AWS CLI** - 版本 >= 2.0（若使用 SSM 連接）

## 步驟 1: 準備環境

### 1.1 獲取你的公網 IP

```bash
curl -s https://checkip.amazonaws.com
# 結果例如: 203.0.113.10
```

### 1.2 複製 terraform.tfvars

```bash
cd infra/
cp terraform.tfvars.example terraform.tfvars
```

### 1.3 編輯 terraform.tfvars

編輯 `infra/terraform.tfvars`，設置以下值：

```hcl
admin_cidr = "203.0.113.10/32"  # 改為你的公網 IP/32

db_master_password = "強密碼!Master123"      # 改為強密碼
db_wp_password     = "強密碼!Wordpress456"   # 改為強密碼
```

**重要**: 不要將實際的 tfvars 檔案提交到 git，`.gitignore` 已設置過濾。

## 步驟 2: 初始化 Terraform

```bash
cd infra/
terraform init
terraform plan
```

檢查計劃輸出，確認資源配置符合預期：

- 1 個 VPC
- 3 個 Subnet (1 public, 2 private)
- 1 個 IGW 和 2 個 Route Table
- 2 個 Security Group (Web 和 DB)
- 1 個 EC2 實例 (WordPress)
- 1 個 RDS 實例 (MySQL)

## 步驟 3: 部署基礎設施

```bash
terraform apply
```

部署完成後，終端會輸出：

- EC2 公網 IP
- RDS endpoint
- SSH 命令

**部署時間**: 約 10-15 分鐘

## 步驟 4: 驗證架構

### 驗證 1: 存取 WordPress

```bash
# 使用輸出中的 WordPress URL（或手動拼接）
curl -I http://<web_ec2_public_ip>
# 應該回傳 302（重定向到安裝頁）或 200（已安裝）
```

### 驗證 2: 確認 RDS 無外網存取

```bash
# 從本機嘗試連接 RDS（應該逾時）
mysql -h <rds_endpoint> -u master -p
# 預期: 連接逾時（無法連接）
```

### 驗證 3: 確認 Web 可連接 DB

#### 方式 A: 使用 SSH（傳統方式）

```bash
# SSH 進入 Web 伺服器
ssh -i infra/yiweee.pem ubuntu@<web_ec2_public_ip>

# 在 Web 伺服器上測試連接
mysql -h <rds_endpoint> -u wp -p
# 輸入 db_wp_password
# 執行: SELECT 1;
```

#### 方式 B: 使用 SSM Session Manager（推薦，更安全）

```bash
# 查詢 EC2 實例 ID（從 terraform output 或 AWS Console）
aws ec2 describe-instances --filters "Name=tag:Name,Values=ec2-yiweee" --query 'Reservations[0].Instances[0].InstanceId'

# 連接到 EC2
aws ssm start-session --target <instance-id> --region ap-northeast-1

# 在會話中執行相同的 mysql 命令
mysql -h <rds_endpoint> -u wp -p
```

### 驗證 4: 完成 WordPress 安裝

1. 開啟瀏覽器，訪問 `http://<web_ec2_public_ip>`
2. 完成 WordPress 初始設置
3. 發佈一篇測試文章

### 驗證 5: 驗證資料持久化

#### 方式 A: 使用 SSH

```bash
# SSH 進入 Web 伺服器
ssh -i infra/yiweee.pem ubuntu@<web_ec2_public_ip>

# 查詢 WordPress 文章
mysql -h <rds_endpoint> -u wp -p<db_wp_password> wordpress
> SELECT post_title FROM wp_posts WHERE post_type='post';
# 應該看到你發佈的文章標題
```

#### 方式 B: 使用 SSM Session Manager

```bash
# 啟動 SSM 會話
aws ssm start-session --target <instance-id> --region ap-northeast-1

# 查詢 WordPress 文章
mysql -h <rds_endpoint> -u wp -p<db_wp_password> wordpress -e "SELECT post_title FROM wp_posts WHERE post_type='post';"
# 應該看到你發佈的文章標題
```

## 清理資源

部署完成後，如要刪除所有資源以避免額外費用：

```bash
cd infra/
terraform destroy
```

**警告**: 這將刪除所有已建立的 AWS 資源，包括 RDS 資料庫。

## 故障排除

### 問題: RDS 無法存取

**檢查清單**:

1. 確認 Security Group 規則正確
2. 確認 RDS 不是公開的 (`publicly_accessible = false`)
3. 檢查 VPC 和 Subnet 配置

### 問題: WordPress 無法連接資料庫

1. SSH 進入 EC2 檢查 logs: `tail -f /var/log/apache2/error.log`
2. 驗證 MySQL 用戶是否建立: `mysql -h <endpoint> -u master -p`
3. 檢查 `wp-config.php` 中的數據庫密碼是否正確

### 問題: user_data 執行失敗

檢查 EC2 用戶數據日誌：

```bash
ssh -i infra/yiweee.pem ubuntu@<web_ec2_public_ip>
tail -f /var/log/cloud-init-output.log
```

## 額外說明

- **密鑰檔案**: 私鑰檔案 `yiweee.pem` 自動生成於 `infra/` 目錄，已在 `.gitignore` 中排除
- **Terraform 狀態**: `*.tfstate` 檔案存儲基礎設施狀態，也已排除於 git 之外
- **架構檔案**: `user_data.sh` 包含 WordPress 和 MySQL 配置腳本

## 相關文件

- [快速開始指南](QUICKSTART.md) - 5 分鐘快速部署
- [項目結構說明](PROJECT_STRUCTURE.md) - Terraform 檔案詳解
- [實作調整總結](IMPLEMENTATION_SUMMARY.md) - 代碼質量和安全性改進
- [應用層配置](../app/README.md) - WordPress 自定義指南

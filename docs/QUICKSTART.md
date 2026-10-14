# 快速開始指南

## ⚡ 5 分鐘快速部署

### 步驟 1：準備（1 分鐘）

```bash
# 取得公網 IP
curl -s https://checkip.amazonaws.com

# 進入 infra 目錄
cd infra/

# 複製配置
cp terraform.tfvars.example terraform.tfvars

# 編輯配置（改成你的 IP、密碼和信箱）
nano terraform.tfvars  # 或用你的編輯器
```

### 步驟 2：初始化（1 分鐘）

```bash
# 初始化 Terraform
terraform init

# 檢查計劃
terraform plan
```

### 步驟 3：部署（10-15 分鐘）

```bash
# 部署所有資源
terraform apply

# 出現提示時輸入 yes
# 等待部署完成
```

部署完成後還有兩件事：

1. 到信箱點擊 AWS Notifications 的確認連結，否則收不到告警信。
2. 等待 user_data 執行完成。登入 Web server 執行 `sudo tail /var/log/cloud-init-output.log`，最後一行出現 `CloudWatch Agent setup complete!` 才算完成。

### 步驟 4：驗證（2 分鐘）

```bash
# 取得 WordPress URL，在瀏覽器中訪問並完成安裝
terraform output -raw wordpress_url
```

---

## 📋 terraform.tfvars 必要配置

```hcl
# 1. 你的公網 IP（SSH 存取）
admin_cidr = "1.2.3.4/32"  # 改為你的 IP

# 2. RDS Master 密碼（8+ 字，大小寫+數字+特殊字)
db_master_password = "MyMaster#2024"

# 3. WordPress 密碼（8+ 字，大小寫+數字+特殊字)
db_wp_password = "MyWP#2024"

# 4. 接收告警信的信箱
alarm_email = "you@example.com"

# 可選：改變區域、實例類型或日誌保留天數
# aws_region = "ap-northeast-1"
# instance_type = "t3.micro"
# log_retention_days = 14
```

VPC 與 Subnet 的 CIDR 也是必填，`terraform.tfvars.example` 已填好，不需更動。

---

## 🔍 快速驗證

以下指令都在 `infra/` 目錄下執行。完整的檢核點驗證步驟（含 P1-2 的故障演練）見 [README](../README.md)。

### 檢查 WordPress 可訪問
```bash
curl -I $(terraform output -raw wordpress_url)
# 未安裝時回傳 302，安裝完成後回傳 200
```

### 檢查 RDS 隔離
```bash
# 從本機嘗試連接（應逾時）
nc -zv -w 5 $(terraform output -raw db_address) 3306
```

### 檢查資料持久化
```bash
# 取得 SSH 指令並登入 EC2
terraform output -raw ssh_command

# 查詢 WordPress 資料（<db_address> 為 terraform output -raw db_address 的值）
mysql -h <db_address> -u wp -p wordpress -e \
  "SELECT post_title FROM wp_posts WHERE post_status='publish';"
```

### 檢查日誌與告警
- CloudWatch 的 log group `/yiweee/web/apache/access` 有一條以 instance ID 命名的 log stream。
- Alarm `alarm-yiweee-http-5xx` 的狀態是 INSUFFICIENT_DATA（沒有 5xx 時的預期狀態）。

---

## 🛠️ 常見命令

```bash
# 檢查部署狀態
terraform show

# 獲取輸出值
terraform output

# 銷毀所有資源（小心！先封存 CloudWatch investigations 的所有調查）
terraform destroy

# 列出將建立的資源
terraform plan -json | jq '.resource_changes[] | select(.change.actions[] | select(. == "create"))'
```

---

## 📚 更多信息

- [架構規劃與驗證步驟](../README.md) - P0-2、P1-2 的設計與檢核點
- [詳細部署指南](SETUP.md) - 完整的部署步驟
- [項目架構](PROJECT_STRUCTURE.md) - Terraform 檔案和專案組織說明
- [WordPress 應用層](../app/README.md) - 應用層配置說明

---

## ⚠️ 重要提醒

1. ✅ **備份 terraform.tfvars** — 包含敏感信息
2. ✅ **檢查 .gitignore** — 確保 *.pem 和 *.tfvars 不被提交
3. ✅ **保存 SSH 密鑰** — yiweee.pem 是 SSH 登入的唯一憑證（另可用 SSM Session Manager 連線）
4. ✅ **注意 AWS 費用** — 部署後會產生費用，記得用完後執行 destroy
5. ✅ **destroy 前先封存調查** — investigation group 內還有進行中的調查時無法刪除，殘留的 group 會讓下次 apply 失敗

---

## 🚀 部署後檢查清單

- [ ] 已點擊 SNS 確認信
- [ ] user_data 執行完成
- [ ] WordPress 前端可訪問
- [ ] RDS 無外網連接（本機連不到）
- [ ] EC2 可連接 RDS
- [ ] 發佈測試文章
- [ ] 重整後文章仍存在
- [ ] Apache 日誌已送進 CloudWatch Logs
- [ ] 備份 terraform.tfvars
- [ ] 備份 SSH 密鑰 (yiweee.pem)

---

## 💡 SSM Session Manager（可選，推薦）

無需 SSH 密鑰也能連接 EC2：

```bash
# 啟動會話
aws ssm start-session --target $(terraform output -raw web_ec2_id) \
  --region ap-northeast-1 --profile course

# 在會話中執行命令
mysql -h <db_address> -u wp -p
```

---

**祝部署順利！** 🎉

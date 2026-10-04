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

# 編輯配置（改成你的 IP 和密碼）
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

### 步驟 4：驗證（2 分鐘）

```bash
# 複製 Terraform output 中的 WordPress URL
# 在瀏覽器中訪問

http://<ec2_public_ip>
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

# 可選：改變區域或實例類型
# aws_region = "ap-northeast-1"
# instance_type = "t3.micro"
```

---

## 🔍 快速驗證

### 檢查 WordPress 可訪問
```bash
curl -I http://<ec2_public_ip>
# 應回傳 302 或 200
```

### 檢查 RDS 隔離
```bash
# 從本機嘗試連接（應超時）
mysql -h <rds_endpoint> -u master -p
# 控制+C 退出
```

### 檢查資料持久化
```bash
# SSH 進入 EC2
ssh -i yiweee.pem ubuntu@<ec2_public_ip>

# 查詢 WordPress 資料
mysql -h <rds_endpoint> -u wp -p<password> wordpress -e \
  "SELECT post_title FROM wp_posts WHERE post_type='post';"
```

---

## 🛠️ 常見命令

```bash
# 檢查部署狀態
terraform show

# 獲取輸出值
terraform output

# 銷毀所有資源（小心！）
terraform destroy

# 查看成本預估
terraform plan -json | jq '.resource_changes[] | select(.change.actions[] | select(. == "create"))'
```

---

## 📚 更多信息

- [詳細部署指南](SETUP.md) - 完整的部署步驟和驗證流程
- [項目架構](PROJECT_STRUCTURE.md) - Terraform 檔案和專案組織說明
- [實作調整](IMPLEMENTATION_SUMMARY.md) - 代碼質量和安全性改進
- [WordPress 應用層](../app/README.md) - 應用層配置說明

---

## ⚠️ 重要提醒

1. ✅ **備份 terraform.tfvars** — 包含敏感信息
2. ✅ **檢查 .gitignore** — 確保 *.pem 和 *.tfvars 不被提交
3. ✅ **保存 SSH 密鑰** — yiweee.pem 是唯一的連接方式
4. ✅ **注意 AWS 費用** — 部署後會產生費用，記得用完後執行 destroy

---

## 🚀 部署後檢查清單

- [ ] WordPress 前端可訪問
- [ ] RDS 無外網連接（本機連不到）
- [ ] EC2 可連接 RDS
- [ ] 發佈測試文章
- [ ] 重啟 EC2 後文章仍存在
- [ ] 備份 terraform.tfvars
- [ ] 備份 SSH 密鑰 (yiweee.pem)

---

## 💡 SSM Session Manager（可選，推薦）

無需 SSH 密鑰也能連接 EC2：

```bash
# 列出 EC2 實例
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=ec2-yiweee" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --region ap-northeast-1

# 啟動會話
aws ssm start-session --target <instance-id> --region ap-northeast-1

# 在會話中執行命令
mysql -h <rds_endpoint> -u wp -p
```

---

**祝部署順利！** 🎉

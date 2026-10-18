# 專案結構

```
wp_agentops/
├── README.md                          # 架構規劃與檢核點驗證步驟（P0-2、P1-2）
├── .gitignore                         # Git 忽略配置
│
├── docs/                              # 說明文件
│   ├── QUICKSTART.md                  # 快速開始指南
│   ├── SETUP.md                       # 部署指南
│   └── PROJECT_STRUCTURE.md           # 本檔案
│
├── infra/                             # Terraform 基礎設施代碼
│   ├── provider.tf                    # Provider 和版本要求
│   ├── variables.tf                   # 變數定義
│   ├── network.tf                     # VPC、Subnet、IGW、SG、Route Table
│   ├── alb.tf                         # ACM 憑證、ALB、target group、listener、Cloudflare DNS 記錄
│   ├── compute.tf                     # EC2、RDS、IAM
│   ├── monitoring.tf                  # P1-2：Log group、metric filter、Alarm、SNS、Dashboard
│   ├── agent.tf                       # P1-2：CloudWatch investigations 的 investigation group 與 IAM role
│   ├── outputs.tf                     # 輸出變數
│   ├── user_data.sh                   # EC2 初始化腳本
│   ├── terraform.tfvars.example       # 變數配置範本
│   └── .terraform.lock.hcl            # Provider 版本與雜湊鎖定檔
│
├── app/                               # WordPress 應用層
│   └── README.md                      # 應用層配置說明
│
├── slides/                            # 簡報素材
│   ├── OUTLINE.md                     # 簡報大綱
│   ├── screenshots/                   # 簡報截圖，不進版控
│   └── secrets/                       # 個人資料，不進版控
│
└── verify/                            # 驗證結果（截圖、指令輸出），內容不進版控
```

## 檔案說明

### 核心 Terraform 檔案

#### `provider.tf`
- AWS provider 配置 (ap-northeast-1 區域)
- AWS CLI profile: 動態配置（var.profile，預設："course"）
- 定義所需的 Provider: aws 5.0+, awscc 1.0+, time 0.9+, cloudflare 4.0+
  - cloudflare: 建立 ACM 的 DNS 驗證記錄與指向 ALB 的網站記錄，token 來自 var.cloudflare_api_token
  - awscc: `aws` provider 尚未支援 CloudWatch investigations，investigation group 改用 Cloud Control 版本建立
  - time: 用 `time_sleep` 等待調查用的 IAM Role 生效
- default_tags: 所有 `aws_*` 資源都帶上 `Project = yiweee` 標籤，供 CloudWatch investigations 劃定調查範圍
- Terraform 最低版本: 1.0

#### `variables.tf`
- AWS 區域與 AWS CLI profile
- VPC CIDR 和 Subnet CIDR
- 實例類型和儲存容量
- 資料庫密碼 (sensitive)
- 網域 (domain_name) 與 Cloudflare API token (cloudflare_api_token，sensitive)
- 告警信箱 (alarm_email) 與日誌保留天數 (log_retention_days)

沒有預設值、必須在 `terraform.tfvars` 提供的變數：五個 CIDR、`db_master_password`、`db_wp_password`、`domain_name`、`cloudflare_api_token`、`alarm_email`。

#### `network.tf`
**VPC 與 Subnet:**
- vpc-yiweee: 10.0.0.0/16
- subnet-yiweee-public-1a: 10.0.1.0/24 (with auto-assign public IP)
- subnet-yiweee-public-1c: 10.0.4.0/24 (只為了滿足 ALB 橫跨兩個 AZ，不放 EC2)
- subnet-yiweee-private-1a: 10.0.2.0/24
- subnet-yiweee-private-1c: 10.0.3.0/24

**路由與 IGW:**
- Internet Gateway (igw-yiweee)
- Public Route Table (指向 IGW 的 0.0.0.0/0)
- Private Route Table (只有 VPC local 路由)

**Security Groups:**
- sg-yiweee-alb: inbound 80、443 來自 0.0.0.0/0；outbound 只放行 80 到 web SG
- sg-yiweee-web: HTTP (80 from ALB SG only)，不開 SSH
- sg-yiweee-db: MySQL (3306 from web SG only)

#### `alb.tf`
- ACM 憑證 (var.domain_name)，以 DNS 驗證；Terraform 在 Cloudflare 自動建立驗證用 CNAME，等簽發完成後才掛到 listener
- ALB (alb-yiweee)：放在 public-1a 與 public-1c，idle timeout 120 秒（故障演練時避免 ALB 先回 504）
- Target group (tg-yiweee-web)：轉送到 EC2 的 80
- Listener：443 掛 ACM 憑證並轉送；80 一律 301 轉導 HTTPS
- Cloudflare 網站記錄：網域 CNAME 指向 ALB，僅 DNS（不經 Cloudflare 代理）

#### `compute.tf`
**EC2:**
- AMI: Ubuntu 22.04 LTS (最新版本)
- Instance Type: t3.micro (可配置)
- User Data: 自動安裝 Apache、PHP、MySQL client、WordPress、CloudWatch Agent
- 儲存: 20GB gp3 卷

**RDS MySQL:**
- Engine: MySQL 8.0
- Instance Class: db.t3.micro (可配置)
- 儲存: 20GB (可配置；未指定 storage_type，使用預設的 gp2)
- 位置: private-1a AZ
- Publicly Accessible: false
- Skip Final Snapshot: true
- Multi-AZ: false

**資料庫:**
- Database Name: wordpress
- Master User: master (密碼來自 var.db_master_password)
- WordPress User: wp (由 user_data 自動建立，密碼來自 var.db_wp_password)

**IAM:**
- EC2 IAM Role (role-yiweee-web)：掛 AmazonSSMManagedInstanceCore（SSM 連線）與 CloudWatchAgentServerPolicy（寫入日誌）
- Instance Profile 關聯

#### `monitoring.tf`
**觀測:**
- Log group: /yiweee/web/apache/access、/yiweee/web/apache/error（保留天數 var.log_retention_days）

**偵測:**
- Metric filter: access log 的 HTTP 5xx → yiweee/WordPress 的 Http5xxCount
- Alarm (alarm-yiweee-http-5xx): 1 分鐘內 ≥ 1 筆即觸發，同時啟動調查與發送 SNS
- SNS topic (sns-yiweee-alarm) 與 email 訂閱 (var.alarm_email)

**視覺化:**
- Dashboard (dashboard-yiweee-wordpress): 只供人工查看，不參與告警與調查，包含 6 個 widget
  - HTTP 5xx 次數趨勢、Alarm 狀態
  - EC2 CPUUtilization、NetworkIn/Out
  - access log 最近的 5xx 請求、error log 最新紀錄

#### `agent.tf`
- Investigation group (ig-yiweee)：使用 `awscc` provider 建立，允許本帳號的 Alarm 建立調查，並以 `Project` 標籤劃定調查範圍
- 調查用 IAM Role (role-yiweee-investigation)：由 aiops.amazonaws.com 擔任，只掛唯讀的 AIOpsAssistantPolicy
- time_sleep：Role 建好後等 30 秒再建立 investigation group

#### `outputs.tf`
**網路資訊:**
- vpc_id, 各 subnet_id
- web 與 db 的 security group ID

**EC2 資訊:**
- 實例 ID、公網 IP、私網 IP
- SSM 命令（便捷用，登入 EC2 的唯一方式）
- WordPress URL（HTTPS 網域）、ALB DNS 名稱、ACM 憑證 ARN
- http_redirect_command：驗證 HTTP 轉導 HTTPS（預期 301）

**RDS 資訊:**
- 資料庫 endpoint（含 port）和 address（不含 port，給 `mysql -h`、`nc` 使用）
- 資料庫名稱


**監控與 Agent:**
- 兩個 log group 名稱、Alarm 名稱、SNS topic ARN、Dashboard 網址 (dashboard_url)
- investigation group ARN

**故障演練:**
- fault_inject_command：移除 db SG 的 3306 規則，重現「DB 連不上」
- fault_probe_command：送出請求並印出 HTTP 狀態碼

### 配置和指南檔案

#### `terraform.tfvars.example`
需要複製為 `terraform.tfvars` 並編輯以下值：
- `db_master_password`: RDS master 密碼
- `db_wp_password`: WordPress DB 用戶密碼
- `alarm_email`: 接收告警信的信箱（apply 後需點擊確認信）
- `domain_name`: 網站網域（DNS 託管在 Cloudflare）
- `cloudflare_api_token`: Cloudflare API token（需 Zone:Read、DNS:Edit）

#### `user_data.sh`
EC2 初始化腳本，包含：
1. 系統更新
2. 安裝 Apache2、PHP、MySQL Client
3. 下載 WordPress
4. 建立 wp-config.php（含 `WP_DEBUG`，讓錯誤寫進 Apache error log）
5. 等待 RDS 可用
6. 建立 WordPress DB 用戶 (wp@10.0.%)
7. 重啟 Apache
8. 安裝 CloudWatch Agent，將 Apache access / error log 送進 CloudWatch Logs

#### `docs/QUICKSTART.md`
最短的部署流程與常用命令

#### `docs/SETUP.md`
完整的部署指南：
- 前置條件
- 環境準備步驟
- Terraform 初始化和部署
- 部署後的基本檢查（正式的檢核點驗證步驟以 README 為準）
- 故障排除指南
- 清理資源方法

### 應用層

#### `app/README.md`
- 應用層目錄說明
- WordPress 自定義指南
- 插件和主題配置方式

## 部署流程圖

```
1. 準備環境
   ├─ 複製 terraform.tfvars.example
   ├─ 編輯 terraform.tfvars
   └─ 執行 terraform init

2. 規劃部署
   └─ 執行 terraform plan

3. 部署資源 (10-15 分鐘)
   └─ 執行 terraform apply
      ├─ 建立 VPC、Subnet、IGW、Security Groups
      ├─ 申請 ACM 憑證、在 Cloudflare 建立驗證記錄、建立 ALB
      ├─ 建立 IAM Role、Log group、metric filter、SNS
      ├─ 建立 investigation group 與 Alarm
      ├─ 建立 RDS MySQL 實例
      └─ 啟動 EC2 實例（等 RDS 建好後才開始）
         └─ 執行 user_data 腳本
            ├─ 安裝 Apache、PHP、WordPress
            ├─ 建立 WordPress DB 用戶
            └─ 安裝 CloudWatch Agent

4. 部署後
   ├─ 點擊 SNS 確認信
   ├─ 等待 user_data 執行完成
   └─ 完成 WordPress 安裝

5. 驗證（步驟見 README）
   ├─ P0-2：五個檢核點
   └─ P1-2：故障演練（偵測 → 判讀 → 處置）

6. 清理 (可選)
   ├─ 封存 CloudWatch investigations 的所有調查
   └─ 執行 terraform destroy
```

## 關鍵特性

✅ **基礎設施即代碼**: 所有資源通過 Terraform 定義
✅ **自動化部署**: user_data 腳本自動配置 WordPress 與 CloudWatch Agent
✅ **安全隔離**: 分層 VPC、子網和 Security Group
✅ **機密管理**: 密碼在 tfvars（排除於 git）
✅ **可重複部署**: 支持多次 apply/destroy
✅ **易於排查**: 詳細的輸出和驗證指南

## 相關文檔

- [架構規劃與驗證步驟](../README.md) - P0-2、P1-2 的設計與檢核點
- [快速開始指南](QUICKSTART.md) - 最短的部署流程
- [詳細部署指南](SETUP.md) - 完整的部署步驟

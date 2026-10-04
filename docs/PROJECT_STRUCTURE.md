# 專案結構

```
wp_agentops/
├── README.md                          # 架構規劃（已有）
├── SETUP.md                          # 部署指南（新增）
├── IMPLEMENTATION_SUMMARY.md         # 實作調整總結（新增）
├── PROJECT_STRUCTURE.md              # 本檔案
├── .gitignore                        # Git 忽略配置（已更新）
│
├── infra/                            # Terraform 基礎設施代碼
│   ├── provider.tf                   # AWS provider 和版本要求
│   ├── variables.tf                  # 變數定義
│   ├── network.tf                    # VPC、Subnet、IGW、SG、Route Table
│   ├── compute.tf                    # EC2、RDS、密鑰、IAM
│   ├── outputs.tf                    # 輸出變數
│   ├── user_data.sh                  # EC2 初始化腳本
│   └── terraform.tfvars.example      # 變數配置範本
│
├── app/                              # WordPress 應用層
│   └── README.md                     # 應用層配置說明
│
└── .git/                             # Git 版本控制
```

## 檔案說明

### 核心 Terraform 檔案

#### `provider.tf`
- AWS provider 配置 (ap-northeast-1 區域)
- AWS CLI profile: 動態配置（var.profile，預設："course"）
- 定義所需的 Provider: aws 5.0+, tls 4.0+, local 2.0+
- Terraform 最低版本: 1.0
- ✨ 已改進：profile 已變數化，避免硬編碼

#### `variables.tf`
- VPC CIDR 和 Subnet CIDR
- AWS 區域配置
- 管理員 IP (admin_cidr)
- 資料庫密碼 (sensitive)
- 實例類型和儲存容量

#### `network.tf` (約 180 行)
**VPC 與 Subnet:**
- vpc-yiweee: 10.0.0.0/16
- subnet-yiweee-public-1a: 10.0.1.0/24 (with auto-assign public IP)
- subnet-yiweee-private-1a: 10.0.2.0/24
- subnet-yiweee-private-1c: 10.0.3.0/24

**路由與 IGW:**
- Internet Gateway (igw-yiweee)
- Public Route Table (指向 IGW 的 0.0.0.0/0)
- Private Route Table (只有 VPC local 路由)

**Security Groups:**
- sg-yiweee-web: HTTP (80), SSH (22 from admin_cidr)
- sg-yiweee-db: MySQL (3306 from web SG only)

#### `compute.tf` (約 130 行)
**EC2:**
- 密鑰對: tls_private_key + aws_key_pair + local_file
- AMI: Ubuntu 22.04 LTS (最新版本)
- Instance Type: t3.micro (可配置)
- User Data: 自動安裝 WordPress、Apache、PHP、MySQL
- 儲存: 20GB gp3 卷

**RDS MySQL:**
- Engine: MySQL 8.0
- Instance Class: db.t3.micro (可配置)
- 儲存: 20GB gp3 (可配置)
- 位置: private-1a AZ
- Publicly Accessible: false
- Skip Final Snapshot: true
- Multi-AZ: false

**資料庫:**
- Database Name: wordpress
- Master User: master (密碼來自 var.db_master_password)
- WordPress User: wp (自動建立，密碼來自 var.db_wp_password)

**IAM:**
- EC2 IAM Role (用於未來擴展)
- Instance Profile 關聯

#### `outputs.tf` (約 50 行)
**網路資訊:**
- vpc_id, 各 subnet_id
- 路由表 ID

**EC2 資訊:**
- 實例 ID、公網 IP、私網 IP
- SSH 命令（便捷用）
- WordPress URL

**RDS 資訊:**
- 資料庫 endpoint 和 address
- 資料庫名稱

**密鑰管理:**
- 密鑰對名稱
- 私鑰檔案路徑（sensitive）

### 配置和指南檔案

#### `terraform.tfvars.example`
需要複製為 `terraform.tfvars` 並編輯以下值：
- `admin_cidr`: 你的公網 IP (CIDR 格式)
- `db_master_password`: RDS master 密碼
- `db_wp_password`: WordPress DB 用戶密碼

#### `user_data.sh`
EC2 初始化腳本，包含：
1. 系統更新
2. 安裝 Apache2、PHP、MySQL Client
3. 下載 WordPress
4. 建立 wp-config.php
5. 等待 RDS 可用
6. 建立 WordPress DB 用戶 (wp@10.0.1.%)
7. 啟動 Apache

#### `SETUP.md`
完整的部署指南：
- 前置條件
- 環境準備步驟
- Terraform 初始化和部署
- 5 個檢核點驗證方法
- 故障排除指南
- 清理資源方法

#### `IMPLEMENTATION_SUMMARY.md`
本次實作調整的總結報告

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
      ├─ 建立 VPC、Subnet、IGW
      ├─ 建立 Security Groups
      ├─ 啟動 EC2 實例
      │  └─ 執行 user_data 腳本
      │     ├─ 安裝 Apache、PHP
      │     └─ 下載 WordPress
      └─ 建立 RDS MySQL 實例

4. 驗證架構
   ├─ 檢查 WordPress 可存取 (HTTP)
   ├─ 驗證 RDS 無外網存取
   ├─ 驗證 Web→DB 連接
   ├─ 完成 WordPress 安裝
   └─ 測試資料持久化

5. 清理 (可選)
   └─ 執行 terraform destroy
```

## 關鍵特性

✅ **基礎設施即代碼**: 所有資源通過 Terraform 定義
✅ **自動化部署**: user_data 腳本自動配置 WordPress
✅ **安全隔離**: 分層 VPC、子網和 Security Group
✅ **機密管理**: 密碼在 tfvars（排除於 git）
✅ **可重複部署**: 支持多次 apply/destroy
✅ **易於排查**: 詳細的輸出和驗證指南

## 相關文檔

- [快速開始指南](QUICKSTART.md) - 5 分鐘快速部署
- [詳細部署指南](SETUP.md) - 完整的部署步驟和驗證
- [實作調整總結](IMPLEMENTATION_SUMMARY.md) - 代碼質量評分


# WordPress Web/DB 分層實作

## 核心檢核點

1. VPC 切出 public / private 兩個 subnet
2. Web 在 public，外部瀏覽得到網站
3. DB（RDS 或自架 MySQL）在 private，外網連不到（此條最能驗證真的懂分離）
4. SG 串接：只允許 Web 的 SG 連 DB:3306
5. 發一篇文章、重整後仍在（確認寫入 DB）

## 架構說明

- 網路設定:
  1. 建立一個 VPC (vpc-yiweee)，CIDR 設定為 `10.0.0.0/16`。
  2. VPC 下切出 public 一個、private 兩個共計三個網段，名稱分別為 subnet-yiweee-public-1a(`10.0.1.0/24`)、subnet-yiweee-private-1a(`10.0.2.0/24`)、subnet-yiweee-private-1c(`10.0.3.0/24`)。
  3. public 網段的 `0.0.0.0/0` 指向 IGW，並啟動內部機器自動配發對外 IP；private 網段只有 VPC 內的 local 路由，不對外。

- 運算資源:
  1. 在 public 網段下，放一台 EC2 作為 Web server(機器名 ec2-yiweee，部署 WordPress)。
  2. 在 private 網段下，放一台 RDS 作為 DB server(機器名 rds-yiweee，選擇 MySQL)，採用 RDS 簡化 MySQL 部署設定等繁瑣步驟。
  3. Web server 的 EC2 先以本機私鑰作為登入手段，並在 Web server 上跑 MySQL client 維護。
  4. RDS 需要補以下設定：

  ```
  publicly_accessible = false             # 為了檢核點 3 的證據
  skip_final_snapshot = true              # 確保 terraform destroy 可正常執行
  availability_zone   = "ap-northeast-1a" # 確保 RDS 挑到 1a 的 AZ
  ```

  5. RDS 採 single-AZ，且僅放於 subnet-yiweee-private-1a 中，subnet-yiweee-private-1c 網段只是為了滿足 DB subnet group 的要求。

- SG 設定:
  1. DB server 的 inbound 只放行 3306，來源限制為 Web server 的 SG。
  2. Web server 的 inbound 放行 80，來源 `0.0.0.0/0`；22，來源 `[維護人員的 IP]`。
  3. DB server 和 Web server 的 outbound 先全開。

## RDS(MySQL) 與 WordPress 串接設定

1. 在 MySQL 中建立限定來源的帳號（例如 `'wp'@'10.0.1.%'`），並只授權 WordPress 用的資料庫。從 Web server 用 master 帳號連進去創建 `wp` 帳號。
2. 並把 WordPress 的 `wp-config.php` 中的 `DB_HOST` 指向 RDS 的 DNS 名稱(endpoint)。
3. 1 與 2 的操作放入 Web server 的 user_data 一併處理。

## 機密管理

1. Web server 一台 EC2 的私鑰，產生後存放到 infra 的根目錄。
2. DB server 的連線密碼會在 Web server 上的 `wp-config.php` 明文儲存。
3. DB 的連線密碼(WordPress 程式透過帳號 `wp` 存取)，將用 user_data 自動寫入 Web server 的程式，且所有密碼(含 `master`、`wp` 等帳號都算)的來源寫在 `*.tfvars` 避免洩漏。因採 user_data 自動化，兩組密碼仍會以明文方式留存在 tfstate 和 Web server 的 user_data，為求整體自動化順暢，此為已知取捨。
4. 要有 `.gitignore` 避免 infra 的機密資訊如 `*.pem`、`*.tfstate*`、`.terraform/`、`*.tfvars` 被公開。

## 實作改進亮點

### ✨ 基礎設施即代碼（IaC）
- ✅ 完整的 Terraform 配置（provider、variables、network、compute、outputs）
- ✅ 所有配置參數化，易於重複部署到多個環境
- ✅ 自動化 user_data 腳本，EC2 啟動即完成 WordPress 部署

### ✨ 安全性設計
- ✅ 分層網路隔離（public/private 子網）
- ✅ 安全組細粒度控制（Web: 80/22、DB: 3306 from web only）
- ✅ RDS 私有部署（publicly_accessible = false）
- ✅ SSM Session Manager 支持（無需 SSH 密鑰即可連接）
- ✅ 敏感資訊管理（密碼在 tfvars，排除於 git）

### ✨ 架構設計
- ✅ 跨 AZ 子網配置（為未來 Multi-AZ 準備）
- ✅ 自動化密碼和用戶管理（master / wp 帳號分離）
- ✅ 自動等待 RDS 就緒再配置（確保部署穩定）
- ✅ WordPress Salt Key 隨機生成（安全最佳實踐）

## 檢核點驗證規劃

- **檢核點 1**：AWS web console 上顯示一個 VPC、三個網段截圖；兩張 route table 的截圖，證明指向方向正確。
- **檢核點 2**：從外部 `curl -I http://<web server 的對外 IP>` 回 302 導向安裝頁。完成安裝後再連線一次，回 200 成功。
- **檢核點 3**：從本機連 RDS endpoint 的 3306 逾時（驗證隔離）。
- **檢核點 4**：從 Web server 執行 `nc -zv <endpoint> 3306`，預期會成功；在 VPC 內部臨時起一台 EC2 且掛不同 SG，發起連線預期會失敗。臨時 EC2 測試完後刪除。
- **檢核點 5**：發文後在 Web server 用 mysql 查 `SELECT post_title FROM wp_posts` 看得到。

## 部署資源

| 文件 | 說明 |
|------|------|
| 📖 [快速開始](docs/QUICKSTART.md) | 5 分鐘快速部署指南 |
| 📚 [詳細部署指南](docs/SETUP.md) | 完整的部署步驟和驗證流程 |
| 🏗️ [項目結構](docs/PROJECT_STRUCTURE.md) | Terraform 檔案和專案組織說明 |
| 🔧 [實作調整總結](docs/IMPLEMENTATION_SUMMARY.md) | 本次實作的改進和評分 |
| 💻 [應用層配置](app/README.md) | WordPress 應用層說明 |

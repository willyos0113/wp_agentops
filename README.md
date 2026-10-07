# P0-2 | WordPress Web/DB 分離（多組件經典架構）

---

## 目標

- 實現 EC2 + RDS 的 web/db 分離架構，並完成下方檢核點項目。

## 核心檢核點

1. VPC 切出 public / private 兩個 subnet
2. Web 在 public，外部瀏覽得到網站
3. DB（RDS 或自架 MySQL）在 private，外網連不到（此條最能驗證真的懂分離）
4. SG 串接：只允許 Web 的 SG 連 DB:3306
5. 發一篇文章、重整後仍在（確認寫入 DB）

## 架構說明

### 網路設定:

1. 建立一個 VPC (vpc-yiweee)，CIDR 設定為 `10.0.0.0/16`。
2. VPC 下切出 public 一個、private 兩個共計三個網段，名稱分別為 subnet-yiweee-public-1a(`10.0.1.0/24`)、subnet-yiweee-private-1a(`10.0.2.0/24`)、subnet-yiweee-private-1c(`10.0.3.0/24`)。
3. public 網段的 `0.0.0.0/0` 指向 IGW，並啟動內部機器自動配發對外 IP；private 網段只有 VPC 內的 local 路由，不對外。

### 運算資源:

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

### Security group 設定:

1. DB server 的 inbound 只放行 3306，來源限制為 Web server 的 SG。
2. Web server 的 inbound 放行 80，來源 `0.0.0.0/0`；22，來源 `[維護人員的 IP]`。
3. DB server 和 Web server 的 outbound 先全開。

## RDS(MySQL) 與 WordPress 串接設定

1. 在 MySQL 中建立限定來源的帳號（例如 `'wp'@'10.0.1.%'`），並只授權 WordPress 用的資料庫。從 Web server 用 master 帳號連進去創建 `wp` 帳號。
2. 並把 WordPress 的 `wp-config.php` 中的 `DB_HOST` 指向 RDS 的 DNS 名稱(endpoint)。
3. 1 與 2 的操作放入 Web server 的 user_data 一併處理。

## Credential 管理

1. Web server 一台 EC2 的私鑰，產生後存放到 infra 的根目錄。
2. DB server 的連線密碼會在 Web server 上的 `wp-config.php` 明文儲存。
3. DB 的連線密碼(WordPress 程式透過帳號 `wp` 存取)，將用 user_data 自動寫入 Web server 的程式，且所有密碼(含 `master`、`wp` 等帳號都算)的來源寫在 `*.tfvars` 避免洩漏。因採 user_data 自動化，兩組密碼仍會以明文方式留存在 tfstate 和 Web server 的 user_data，為求整體自動化順暢，此為已知取捨。
4. 要有 `.gitignore` 避免 infra 的機密資訊如 `*.pem`、`*.tfstate*`、`.terraform/`、`*.tfvars` 被公開。

## 實作改進亮點

### ✨ 基礎設施即代碼（IaC）:

- ✅ 完整的 Terraform 配置（provider、variables、network、compute、outputs）
- ✅ 所有配置參數化，易於重複部署到多個環境
- ✅ 自動化 user_data 腳本，EC2 啟動即完成 WordPress 部署

### ✨ 安全性設計:

- ✅ 分層網路隔離（public/private 子網）
- ✅ 安全組細粒度控制（Web: 80/22、DB: 3306 from web only）
- ✅ RDS 私有部署（publicly_accessible = false）
- ✅ SSM Session Manager 支持（無需 SSH 密鑰即可連接）
- ✅ 敏感資訊管理（密碼在 tfvars，排除於 git）

### ✨ 架構設計:

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

| 文件                                              | 說明                         |
| ------------------------------------------------- | ---------------------------- |
| 📖 [快速開始](docs/QUICKSTART.md)                 | 5 分鐘快速部署指南           |
| 📚 [詳細部署指南](docs/SETUP.md)                  | 完整的部署步驟和驗證流程     |
| 🏗️ [項目結構](docs/PROJECT_STRUCTURE.md)          | Terraform 檔案和專案組織說明 |
| 🔧 [實作調整總結](docs/IMPLEMENTATION_SUMMARY.md) | 本次實作的改進和評分         |
| 💻 [應用層配置](app/README.md)                    | WordPress 應用層說明         |

# P1-2 | WordPress + 維運 Agent

---

## 目標

- 目的：實現 cloudwatch + amazonQ 完成上述檢核點項目。

## 核心檢核點

1. Agent 能讀取 Web／DB 的日誌或健康狀態
2. 重現「網站 500」或「DB 連不上」情境，Agent 能定位並給建議
3. 完整示範一次 偵測 → 判讀 → 處置
4. Agent 本身也跑在 AWS 上（EC2 或 Lambda），非只在本機執行

## 架構說明

P1-2 疊加在 P0-2 之上，不動既有的網路、SG、RDS，只新增一條「觀測 → 偵測 → 判讀 → 處置」的線。檢核點中的 Agent 指的是「會判讀的維運 Agent」，不是 CloudWatch Agent（後者只是把日誌搬上雲的工具）。

```
Web 日誌 / RDS 指標 → CloudWatch → Alarm ─┬→ Amazon Q 調查（判讀）──┬→ 通知維護人員 → 人工處置
                                         └→ SNS → Lambda（蒐證）─┘
```

CloudWatch 與 Amazon Q 是本階段的必要組件：CloudWatch 負責觀測與偵測，Amazon Q 負責判讀。其餘組件（SNS、Lambda）只是把兩者串起來。

### 觀測資料（Agent 讀什麼）:

1. Web：在 ec2-yiweee 上安裝 CloudWatch Agent，把 Apache 的 access log 與 error log 送進 CloudWatch Logs。
2. DB：直接使用 RDS 內建指標（連線數、CPU 等）與 instance 狀態，不開啟 RDS 的 log 匯出，維持「不改 P0-2 資源」的原則。
3. P0-2 唯一需要調整的地方是 Web server：IAM role 多一個寫入 CloudWatch 的權限、user_data 多一段安裝 CloudWatch Agent。
4. user_data 只在首次開機執行，因此 Web server 需要重建才會生效；文章資料在 RDS 不受影響，此為已知取捨。

### 偵測（何時叫醒 Agent）:

1. 用 metric filter 把 access log 中的 HTTP 5xx 轉成指標，超過門檻即觸發 Alarm。
2. Alarm 觸發時同時做兩件事：啟動 Amazon Q 調查、發到 SNS（寄信給維護人員並叫醒 Lambda）。
3. 只做 HTTP 5xx 這一條告警。CPU／記憶體／磁碟告警與 Dashboard 不在檢核點範圍內，先不做。

### 判讀（Agent 本體）:

1. 維運 Agent 由兩個部分組成：Amazon Q 負責判讀（大腦），Lambda 負責蒐證與通知（手腳）。
2. Amazon Q 的落地形式是 CloudWatch investigations（原名 Amazon Q Developer operational investigations）。在帳號內建立一個 investigation group，並把它設為 Alarm 的 action，Alarm 一響就自動開始調查。
3. Amazon Q 會自行掃描相關的日誌、指標與變更紀錄，產出「根因假設 + 建議處置」。
4. Lambda（機器名 lambda-yiweee-agent）對應檢核點 4：被 SNS 叫醒後，蒐集最近幾分鐘的 Web 日誌、RDS 狀態、DB SG 現況，整理成摘要寄給維護人員。
5. Lambda 只透過 AWS API 讀資料，不直連 Web 或 DB，因此不需要放進 VPC，也不需要動任何 SG。
6. Amazon Q 無法由 Lambda 以 IAM role 直接呼叫（CLI 版本只接受 Builder ID／Identity Center 登入），所以判讀交給 Alarm 直接觸發，Lambda 不經手，此為已知取捨。

### 處置:

1. Agent 只讀不改：維護人員收到通知後，到 CloudWatch 查看 Amazon Q 的調查結果，由人依建議執行處置。
2. 不做自動修復：自動改 SG 或重啟服務需要寫入權限，誤判的代價高，而檢核點 3 只要求完整示範一次流程，此為已知取捨。

## 故障情境設計

1. 主情境選「DB 連不上」：手動移除 DB SG 的 3306 inbound 規則。
2. WordPress 連不上 DB 時會回 HTTP 500，因此一個情境同時涵蓋「網站 500」與「DB 連不上」兩種症狀。
3. 選這個做法的理由：立即生效、不需停 RDS（停止與啟動各要數分鐘）、用 `terraform apply` 即可還原。
4. 預期的判讀路徑：Web 日誌出現大量 500 → RDS 本身狀態正常 → 問題在兩者之間 → DB SG 少了 3306 規則。

## 權限與 Credential 管理

1. 全部透過 IAM role 授權，P1-2 不新增任何長期金鑰或密碼。
2. Web server 的 role 新增 `CloudWatchAgentServerPolicy`，只為了寫入日誌。
3. Lambda 的 role 採最小權限：讀 CloudWatch Logs／指標、查 RDS 與 SG 狀態、發 SNS，沒有任何修改資源的權限。
4. Amazon Q 調查使用獨立的 role（由 `aiops.amazonaws.com` 擔任），同樣只有唯讀權限。
5. 告警收件信箱寫在 `*.tfvars`，沿用 P0-2 的 `.gitignore`。
6. Log group 設定保留天數，避免日誌（含訪客 IP）無限累積。

## 檢核點驗證規劃

- **檢核點 1**：Lambda 寄出的摘要信中有它讀回的 Web 日誌片段與 RDS 狀態；Amazon Q 調查頁面列出它引用的日誌與指標。
- **檢核點 2**：移除 3306 規則後，Amazon Q 調查頁面的根因假設指向 DB 連線失敗與 DB SG，並附上建議處置（截圖）。
- **檢核點 3**：整理一次完整時間軸：Alarm 觸發 → Amazon Q 調查完成 → 依建議 `terraform apply` 還原 → `curl` 回 200 且 Alarm 回到 OK。
- **檢核點 4**：AWS web console 上的 Lambda 函式截圖，以及它被 SNS 觸發的執行紀錄，證明不是在本機執行；Amazon Q 調查本身也是 AWS 上的受管服務。

## 部署資源

| 文件                                                             | 說明                                                               |
| ---------------------------------------------------------------- | ------------------------------------------------------------------ |
| 📝 `infra/monitoring.tf`（待建）                                 | 觀測與偵測：Log group、metric filter、Alarm、SNS                   |
| 📝 `infra/agent.tf`（待建）                                      | 維運 Agent：Amazon Q investigation group、Lambda 與各自的 IAM role |
| 🔧 `infra/compute.tf`、`infra/user_data.sh`（待修改）            | Web server 的 IAM 權限與 CloudWatch Agent 安裝                     |
| 📖 [CloudWatch 練習](practice/cloudwatch/CLOUDWATCH_PRACTICE.md) | CloudWatch 操作練習紀錄                                            |

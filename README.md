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

- 以現有 P0-2 架構為基礎。
- 目的：實現 cloudwatch + amazonQ 完成上述檢核點項目。

## 核心檢核點

1. Agent 能讀取 Web／DB 的日誌或健康狀態
2. 重現「網站 500」或「DB 連不上」情境，Agent 能定位並給建議
3. 完整示範一次 偵測 → 判讀 → 處置
4. Agent 本身也跑在 AWS 上（EC2 或 Lambda），非只在本機執行

## 架構設計原則

基於 P0-2 的穩定基礎，P1-2 在 EC2 + RDS 上疊加**監控與自動化層**，不修改既有的網路、計算、安全組配置。

**核心設計**：將系統觀測數據（日誌、指標）集中到 CloudWatch，透過 AmazonQ 進行智能分析，Lambda 實現自動響應。

**分階段實施**：Phase 1（基礎監控）→ Phase 2（日誌分析）→ Phase 3（自動化）

---

## 監控基礎設定

P1-2 **不改變** P0-2 的網路、計算、安全組架構，僅在以下方向擴展：

1. **IAM 角色擴展**
   - P0-2 中 EC2 已有 `AmazonSSMManagedInstanceCore` 權限（SSM 連線）
   - P1-2 新增：`CloudWatchAgentServerPolicy`（允許 Agent 寫入 Logs/Metrics）
   - Terraform 文件：`compute.tf` 中的 `aws_iam_role_policy_attachment`

2. **CloudWatch 日誌群組預創建**
   - 3 個獨立的 Log Group：
     - `/aws/ec2/wordpress/application` - WordPress 應用日誌（error.log、access.log）
     - `/aws/ec2/wordpress/system` - EC2 系統日誌（syslog、auth.log）
     - `/aws/rds/mysql/slowquery` - RDS 慢查詢日誌（可選，Phase 2）
   - Terraform 文件：新增 `monitoring.tf`

---

## 監控資源配置

#### **1. CloudWatch Agent 部署與配置**

**部署位置**：ec2-yiweee（WordPress 主機）

**安裝方式**（集成至 user_data）：
```bash
# user_data.sh 新增段落
1. 下載 CloudWatch Agent
2. 生成 Agent 配置文件（JSON）
3. 啟動 Agent 服務
4. 驗證 Agent 是否上報數據
```

**Agent 收集的數據**：
- **系統指標**（每分鐘上報）：
  - `CPUUtilization` - CPU 使用率（%）
  - `MemoryUtilization` - 記憶體使用率（%）
  - `DiskUsed` - 磁碟使用量（GB）
  - `NetworkIn/NetworkOut` - 網路流量

- **應用日誌**（即時轉送）：
  - WordPress error.log → `/aws/ec2/wordpress/application`
  - WordPress access.log → `/aws/ec2/wordpress/application`

- **系統日誌**（即時轉送）：
  - /var/log/syslog → `/aws/ec2/wordpress/system`
  - /var/log/auth.log → `/aws/ec2/wordpress/system`

- **自訂指標**（基於日誌解析）：
  - 每分鐘統計 ERROR 日誌出現次數
  - 每分鐘統計 DB 連線失敗次數

#### **2. CloudWatch Logs 配置**

**Metric Filters 規則**（在 Log Group 中設置）：

| Filter 名稱 | Log Group | 篩選模式 | 生成指標 | 閾值 |
|-----------|----------|--------|--------|------|
| `ErrorLogCount` | `/aws/ec2/wordpress/application` | `[ERROR]` 或 `ERROR` | `ErrorCount` | > 10（5min） |
| `DBConnectionFailed` | `/aws/ec2/wordpress/application` | `database connection failed` 或 `DB Error` | `DBFailCount` | > 5（5min） |
| `HTTP500Error` | `/aws/ec2/wordpress/application` | `HTTP/1.1" 500` | `HTTP500Count` | > 3（5min） |

---

## 告警與儀表板設定

#### **3. CloudWatch Alarms 配置**

基於上述指標，建立告警規則：

| 告警名稱 | 監控指標 | 條件 | 觸發動作 | 優先度 |
|---------|--------|------|---------|------|
| `CPUHigh` | `CPUUtilization` | > 80%（連續 2 個 5min） | SNS 通知 | 🔴 High |
| `MemoryHigh` | `MemoryUtilization` | > 90%（連續 2 個 5min） | SNS 通知 | 🔴 High |
| `DiskFull` | `DiskUsed` | > 90%（連續 1 個 5min） | SNS 通知 | 🟠 Medium |
| `ErrorSpike` | `ErrorCount` | > 10（連續 1 個 5min） | SNS + Lambda 通知 | 🟠 Medium |
| `DBConnFailed` | `DBFailCount` | > 5（連續 1 個 5min） | SNS + Lambda 通知 | 🔴 High |

**SNS 話題**：
- 話題名稱：`cloudwatch-alerts-yiweee`
- 訂閱方式：郵件（維護人員信箱）
- 後期擴展：Lambda 函數

#### **4. CloudWatch Dashboards 配置**

**儀表板名稱**：`WordPress-RDS-Monitoring`

**版面配置**：
```
┌─────────────────────────────────────────────────┐
│ 系統健康狀態（實時）                             │
├──────────┬──────────┬──────────┬──────────────┤
│ CPU %    │ Mem %    │ Disk %   │ Network In   │
│ [00.5%]  │ [45.2%]  │ [62.1%]  │ [12.3 MB/s]  │
└──────────┴──────────┴──────────┴──────────────┘

┌─────────────────────────────────────────────────┐
│ 應用層指標（Last 1 Hour）                       │
├──────────┬──────────┬──────────┬──────────────┤
│ ERROR日誌│ DB 連線  │ HTTP 500 │ 警告次數     │
│ 線圖     │ 線圖     │ 線圖     │ 數字展示     │
└──────────┴──────────┴──────────┴──────────────┘

┌─────────────────────────────────────────────────┐
│ 告警歷史（Last 24 Hours）                       │
│ [Recent Alarms Table]                          │
└─────────────────────────────────────────────────┘
```

**小部件配置**：
- 系統指標：4 個 Number widget（CPU、Memory、Disk、Network）
- 應用層：3 個 Line graph（ERROR、DB Fail、HTTP500）
- 告警狀態：1 個 Alarm Status widget

---

## 日誌與指標整合

#### **5. 日誌分析工作流**

**正常情況**：
```
EC2 應用日誌
  ↓
CloudWatch Agent（local buffer）
  ↓
CloudWatch Logs（Log Stream）
  ↓
Metric Filter 解析
  ↓
CloudWatch Metrics（自訂指標）
  ↓
告警判斷 & 儀表板顯示
```

**故障定位工作流**（檢核點 2 驗證）：
```
1. 發現告警（如 HTTP500 > 3）
  ↓
2. 打開 CloudWatch → Logs → 查詢日誌
  ↓
3. CloudWatch Insights 執行查詢
   SQL: fields @timestamp, @message 
        | filter @message like /500/ 
        | stats count() by @message
  ↓
4. 定位具體的錯誤信息和堆棧
  ↓
5. 登入 EC2（SSM Session Manager）查看應用狀態
```

#### **6. AmazonQ 整合（Phase 2）**

**使用場景**：
- 將 CloudWatch Logs 查詢結果複製給 AmazonQ
- 詢問："這個 WordPress 500 錯誤是什麼原因？"
- AmazonQ 分析日誌並給出根因診斷

**配置細節**：
- AmazonQ Web Experience 或 IDE 插件
- 登入 AWS Console 無需額外配置
- 實踐中直接使用（無 Terraform 基礎設施）

---

## 自動化與凭證管理

#### **7. Lambda 自動化（Phase 3，可選）**

**觸發邏輯**：
```
CloudWatch Alarm 觸發
  ↓
SNS Topic 發送通知
  ↓
Lambda Function 訂閱 SNS
  ↓
根據告警類型執行不同邏輯：
  - 高 CPU：記錄診斷信息，發送郵件
  - DB 連線失敗：嘗試重新連線，記錄日誌
  - 日誌異常：自動調用修復腳本
```

**Lambda 環境變數**：
- `SNS_TOPIC_ARN` - 告警通知話題
- `DB_ENDPOINT` - RDS 端點
- `LOG_GROUP_NAME` - CloudWatch Log Group

#### **8. 凭證管理**

P1-2 引入的新凭證：
- **CloudWatch Agent 配置檔**：存儲在 EC2`/opt/aws/amazon-cloudwatch-agent/` 目錄（不涉及密鑰）
- **SNS Topic ARN**：存儲在 Terraform variables
- **Lambda 執行角色**：IAM 角色（Phase 3 新增）

**敏感資訊排除**：
- 新增 `.gitignore` 條目（如需本地配置文件）
- SNS 郵件地址參數化至 `terraform.tfvars`
- Lambda 密鑰透過 AWS Secrets Manager（後期優化）

---

## 實作改進亮點

### ✨ 可觀測性（Observability）

- ✅ 系統與應用日誌完全集中到 CloudWatch Logs
- ✅ 自動解析日誌生成自訂指標（ERROR、DB 連線失敗、HTTP 500）
- ✅ 統一儀表板展示系統全景（CPU、記憶體、磁碟、應用狀態）

### ✨ 故障檢測與診斷

- ✅ 多維度告警機制（系統層、應用層）
- ✅ 日誌查詢工具快速定位故障根因
- ✅ AmazonQ AI 輔助分析複雜故障

### ✨ 自動化與智能化

- ✅ 告警驅動的 Lambda 自動響應（Phase 3）
- ✅ SNS 多渠道通知（郵件、Lambda 觸發）
- ✅ 完整的偵測→判讀→處置工作流

---

## Terraform 與部署規劃

### Terraform 文件結構

**現有文件**（P0-2，保持不動）：
- `network.tf` - VPC、Subnet、IGW、Route Table、Security Group
- `compute.tf` - EC2、RDS、IAM、Key Pair
- `variables.tf` - 變數定義
- `outputs.tf` - 輸出值
- `user_data.sh` - EC2 初始化腳本

**新增文件**（P1-2）：

**Phase 1 新增**：
- `monitoring.tf`
  - IAM 角色擴展（CloudWatchAgentServerPolicy）
  - CloudWatch Log Groups（3 個）
  - Metric Filters（3 個）

**Phase 2 新增**（集成至 monitoring.tf）：
- CloudWatch Alarms（5-8 個）
- SNS Topic 與訂閱
- CloudWatch Dashboard

**Phase 3 新增**：
- `automation.tf`
  - Lambda IAM 角色與權限
  - Lambda 函數定義
  - SNS → Lambda 訂閱規則

**修改文件**：
- `compute.tf` 
  - 第 92-95 行：IAM 角色新增 CloudWatchAgentServerPolicy
- `user_data.sh`
  - 新增 Agent 下載、安裝、配置段落
  - 新增配置文件模板（JSON）
- `terraform.tfvars`
  - 新增：`alert_email`（告警郵箱）
  - 新增：`alarm_thresholds`（告警閾值）
- `variables.tf`
  - 新增上述變數定義

---

## 檢核點驗證規劃

### 逐點驗證方法

| # | 檢核點 | Phase | 驗證步驟 | 預期結果 | 驗證證據 |
|---|------|-------|--------|--------|--------|
| **1** | Agent 讀取日誌/健康狀態 | Phase 1 | 登入 CloudWatch → Logs → 查看 Log Stream | 能看到實時的應用和系統日誌 | Log Stream 截圖 |
| **2** | 定位故障（500 or DB 連不上） | Phase 2 | 故意停止 RDS / 製造 WordPress 錯誤，用 Insights 查詢 | 能在日誌中找到明確的錯誤信息和堆棧 | 查詢結果截圖 + 分析報告 |
| **3** | 完整示範偵測→判讀→處置 | Phase 3 | 記錄完整流程：告警觸發 → AmazonQ 診斷 → Lambda 修復 | 流程完整且有效 | 流程記錄 + 截圖組合 |
| **4** | Agent 在 AWS 上運行 | Phase 1 | 登入 CloudWatch → Metrics → Browse → CWAgent namespace | 能看到 cpu、mem、disk 等指標 | Metrics 截圖 |

### 製造故障場景清單

| 故障類型 | 製造方式 | 預期症狀 | 驗證指標 |
|---------|--------|--------|--------|
| **高 CPU** | 執行 `stress-ng` 或密集計算 | CPU > 80% | CloudWatch CPUUtilization |
| **高記憶體** | 執行記憶體洩漏腳本 | Memory > 90% | CloudWatch MemoryUtilization |
| **滿磁碟** | 寫入大文件至磁碟 | DiskUsed > 90% | CloudWatch DiskUsed |
| **DB 連線失敗** | 修改 RDS Security Group / 停止 RDS | DB 連線失敗日誌 | ERROR 日誌計數 > 5 |
| **WordPress 500 錯誤** | 修改 wp-config.php / 禁用關鍵插件 | HTTP 500 日誌 | HTTP500Count > 3 |

---

## 部署資源

本階段需要參考的文檔：

| 文件 | 用途 | 狀態 |
|------|------|------|
| 📖 `LEARNING_ROADMAP.md` | 3 階段學習計畫與時間估算 | ✅ 已編寫 |
| 📝 `infra/monitoring.tf`（待建） | CloudWatch 基礎設施代碼 | 📋 計畫中 |
| 📝 `infra/automation.tf`（待建） | Lambda 與 SNS 代碼 | 📋 計畫中 |
| 📖 `practice/cloudwatch-agent/`（待建） | CloudWatch Agent 學習練習 | 📋 計畫中 |

---

## 下一步行動

**推薦步驟順序**：

1. **Day 1-2**：新增 `monitoring.tf`（Phase 1）+ 修改 `compute.tf`、`user_data.sh`、`variables.tf`
2. **Day 3-4**：部署至測試環境，驗證 Agent 正常運作 ✅ 檢核點 1 & 4
3. **Day 5-7**：新增 Alarms + Dashboard（Phase 2），製造故障場景測試 ✅ 檢核點 2
4. **Week 2**：`automation.tf`（Phase 3），完整端到端測試 ✅ 檢核點 3
5. **Week 3**：文檔整理與最佳實踐沉澱

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

## 架構說明

### 整體系統架構

```
┌─────────────────────────────────────────────────────────────────────┐
│                    AWS CloudWatch 監控與分析系統                     │
│                                                                     │
│ ┌──────────────────────────────────────────────────────────────┐   │
│ │ CloudWatch（集中監控樞紐）                                   │   │
│ │ ├─ Metrics：系統指標收集與聚合                               │   │
│ │ ├─ Logs：多來源日誌集中存儲                                 │   │
│ │ ├─ Alarms：告警規則與觸發                                   │   │
│ │ └─ Dashboards：統一可視化展板                               │   │
│ └──────────────────────────────────────────────────────────────┘   │
│                        ▲                    ▲                       │
│                        │                    │                       │
│            ┌───────────┴────────┐  ┌────────┴──────────┐            │
│            │                    │  │                   │            │
│ ┌──────────┴──────────┐ ┌──────┴──┴────────┐ ┌────────┴──────────┐ │
│ │ EC2: CloudWatch    │ │ AmazonQ          │ │ Lambda (後期)     │ │
│ │ Agent + Web/DB     │ │ ├─ 日誌分析      │ │ ├─ 告警響應       │ │
│ │                    │ │ ├─ 故障診斷      │ │ ├─ 自動化修復     │ │
│ │ ├─ CPU/Memory/Disk │ │ └─ 優化建議      │ │ └─ 通知發送       │ │
│ │ ├─ 應用日誌        │ │                  │ │                   │ │
│ │ ├─ 系統日誌        │ │                  │ │                   │ │
│ │ └─ 自訂指標        │ │ (AI 代理分析)   │ │ (自動化處理)      │ │
│ └──────────────────────┘ └──────────────────┘ └───────────────────┘ │
│            ▲                                                         │
│            │                                                         │
│ ┌──────────┴──────────────────────────────────────────────────────┐ │
│ │ RDS MySQL（Web / DB 日誌不在 RDS，通過 Agent 轉送）           │ │
│ └────────────────────────────────────────────────────────────────┘ │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 核心組件與責務

#### 1️⃣ **CloudWatch Agent（EC2 上部署）**
- **安裝位置**：ec2-yiweee（WordPress 主機）
- **收集項目**：
  - 系統指標：CPU、記憶體、磁碟、網路 I/O
  - 應用日誌：WordPress error.log、access.log
  - 系統日誌：/var/log/syslog、/var/log/auth.log
  - 自訂指標：WordPress 插件監控、RDS 連線狀態

- **轉送目標**：CloudWatch Logs（獨立的 Log Group）

#### 2️⃣ **CloudWatch Logs（日誌聚合）**
- **Log Groups**：
  - `/aws/ec2/wordpress` - WordPress 應用日誌
  - `/aws/ec2/system` - EC2 系統日誌
  - `/aws/rds/mysql` - RDS 慢查詢日誌（可選）

- **Metric Filters**：基於日誌內容創建自訂指標
  - ERROR 日誌計數
  - DB 連線失敗計數

#### 3️⃣ **CloudWatch Metrics & Alarms**
- **系統指標告警**：
  - CPU > 80% → 發出告警
  - 記憶體 > 90% → 發出告警
  - 磁碟空間 < 10% → 發出告警

- **應用層告警**：
  - ERROR 日誌數 > 10（5 分鐘內）
  - DB 連線失敗次數 > 5

#### 4️⃣ **CloudWatch Dashboards（實時可視化）**
統一儀表板展示：
- WordPress 運行狀態（快速診斷）
- RDS 連線狀態與查詢性能
- 錯誤日誌趨勢
- 系統資源利用率
- 告警歷史與狀態

#### 5️⃣ **AmazonQ（AI 代理分析）** 
- **使用場景**：
  - 詢問 AmazonQ 分析異常日誌
  - 快速診斷 500 錯誤原因
  - 獲取優化建議
  - 理解複雜的錯誤堆棧

- **輸入來源**：CloudWatch Logs 日誌內容

#### 6️⃣ **Lambda Functions（後期自動化）**
- **觸發方式**：CloudWatch Alarms → SNS → Lambda
- **處理邏輯**：
  - 高 CPU 警告時發送郵件通知
  - DB 連線失敗時記錄詳細診斷信息
  - 日誌異常時調用自動修復腳本

---

### 數據流向與工作流程

#### **正常運行流程**
```
1. CloudWatch Agent 定期收集指標
   ↓
2. 指標上報到 CloudWatch Metrics
   ↓
3. Dashboards 實時顯示系統狀態
   ↓
4. 日誌寫入 CloudWatch Logs
   ↓
5. Metric Filters 解析日誌，生成自訂指標
```

#### **告警與診斷流程**
```
1. 指標超過閾值（如 CPU > 80%）
   ↓
2. CloudWatch Alarm 觸發
   ↓
3. 向 SNS 發送通知（郵件/簡訊）
   ↓
4. 人工登入 CloudWatch 查看日誌
   ↓
5. 詢問 AmazonQ 分析根本原因
   ↓
6. 根據建議進行手動處置或觸發 Lambda 自動修復
```

---

### 與 P0-2 的關係

| 項目 | P0-2（基礎架構） | P1-2（監控擴展） | 變更內容 |
|------|----------------|----------------|--------|
| **EC2** | ✅ 存在 | ✅ 擴展 | 新增 CloudWatch Agent |
| **RDS** | ✅ 存在 | ✅ 監控 | 啟用慢查詢日誌（可選） |
| **IAM 角色** | ✅ SSM 基礎 | ✅ 擴展 | 新增 CloudWatch 寫入權限 |
| **日誌聚合** | ❌ 無 | ✅ 新增 | CloudWatch Logs |
| **告警系統** | ❌ 無 | ✅ 新增 | CloudWatch Alarms + SNS |
| **可視化** | ❌ 無 | ✅ 新增 | CloudWatch Dashboards |
| **AI 分析** | ❌ 無 | ✅ 新增 | AmazonQ（可選） |
| **自動化** | ❌ 無 | ⏳ 計畫 | Lambda（Phase 3） |

---

### 部署策略

#### **Phase 1：基礎監控（Week 1-2）**
```
修改 IAM 角色 → 部署 CloudWatch Agent → 配置 Logs & Metrics → 建立 Dashboards
```

**Terraform 變更**：
- `compute.tf`：IAM 角色新增權限
- 新增 `monitoring.tf`：Agent 配置
- `user_data.sh`：自動部署 Agent

#### **Phase 2：日誌分析（Week 3-4）**
```
配置 Metric Filters → 設置告警規則 → 整合 AmazonQ
```

**Terraform 變更**：
- `monitoring.tf`：告警和過濾器配置

#### **Phase 3：自動化響應（Week 5-6）**
```
創建 Lambda 函數 → SNS 整合 → 自動化流程測試
```

**Terraform 變更**：
- 新增 `automation.tf`：Lambda 和 SNS 配置

---

### 技術棧詳情

| 元件 | 服務 | 用途 | 狀態 |
|------|------|------|------|
| **監控代理** | CloudWatch Agent | 指標與日誌收集 | Phase 1 |
| **日誌存儲** | CloudWatch Logs | 中央日誌倉庫 | Phase 1 |
| **指標聚合** | CloudWatch Metrics | 數據聚合與查詢 | Phase 1 |
| **實時展示** | CloudWatch Dashboards | 統一可視化 | Phase 1 |
| **告警引擎** | CloudWatch Alarms | 條件觸發 | Phase 2 |
| **通知服務** | SNS | 郵件/簡訊通知 | Phase 2 |
| **AI 分析** | AmazonQ | 日誌分析與診斷 | Phase 2 |
| **自動化** | Lambda | 告警響應與修復 | Phase 3 |

---

### 檢核點達成策略

| 檢核點 | 對應 Phase | 驗證方法 |
|------|----------|--------|
| **1. Agent 讀取日誌/健康狀態** | Phase 1 | CloudWatch Logs 能看到實時日誌 |
| **2. 定位故障（500 or DB 連不上）** | Phase 2 | 人工製造故障，通過日誌查詢定位 |
| **3. 完整示範偵測→判讀→處置** | Phase 3 | 記錄告警觸發→AmazonQ 診斷→Lambda 修復的完整流程 |
| **4. Agent 在 AWS 上運行** | Phase 1 | Agent 部署在 EC2 上，CloudWatch 見到指標 |

---

### 預期成果

✅ **Phase 1 完成後**：
- CloudWatch 實時展示 WordPress + RDS 健康狀態
- 所有日誌自動轉送到 CloudWatch Logs
- 儀表板清晰展示系統瓶頸

✅ **Phase 2 完成後**：
- 故障自動告警（郵件/簡訊）
- AmazonQ 快速定位問題根因
- 建立常見故障的診斷手冊

✅ **Phase 3 完成後**：
- 高 CPU 自動降級或通知
- DB 連線失敗自動重試
- 完全自動化的故障響應流程

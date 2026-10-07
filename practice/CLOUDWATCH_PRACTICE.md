# CloudWatch 基礎實戰練習 (30分鐘)

> 在 AWS Web Console 上手 CloudWatch 的快速入門指南

---

## 前置條件

- ✓ 已登入 AWS Console
- ✓ 擁有 CloudWatch、EC2、Lambda 存取權限
- ✓ 瀏覽器可存取 AWS 服務
- **✓ 至少啟動一台 EC2 實例（必需）** - 用於產生 CPU Utilization 指標
  - 如無 EC2，可選用：Lambda 函數、DynamoDB 表、RDS 資料庫等其他服務產生指標

### 快速啟動 EC2 實例

如果還沒有 EC2 實例，可快速建立：

1. **進入 EC2 控制台**

   ```
   https://console.aws.amazon.com/ec2/
   ```

2. **啟動實例**

   ```
   Instances → Launch instances
   → Ubuntu Server 24.04 LTS (t2.micro - 免費套餐)
   → 使用預設設定
   → Launch instance
   ```

   > 或選擇其他 Ubuntu LTS 版本如 22.04、20.04 等

3. **等待實例運行**
   ```
   約 1-2 分鐘後狀態變為 "Running"
   ```

> ⚠️ 務必記下實例 ID 或名稱，練習中會用到
> instance ID: i-036939f7ebe78e531
> public IP: 54.95.75.119

---

## 練習 1: 探索 CloudWatch 控制台 (5分鐘)

### 目標

熟悉 CloudWatch 的主要功能模組

### 操作步驟

1. **打開控制台**
   - 存取 https://console.aws.amazon.com/cloudwatch/

2. **左側選單記憶**
   - `Dashboards` - 自訂儀表板
   - `Alarms` - 警報規則
   - `Logs` - 日誌管理
   - `Metrics` - 指標瀏覽
   - `Events` - 事件規則

### ✓ 驗證檢查

- [x] 能快速找到 Metrics 選單
- [x] 能打開 Alarms 頁面
- [x] 📸 **截圖：CloudWatch 控制台左側選單** (./screenshots/cloudwatch-prac-1.png)

---

## 練習 2: 建立儀表板並新增小部件 (8分鐘)

### 目標

建立自訂儀表板，新增系統指標

### 操作步驟

1. **建立儀表板**

   ```
   Dashboards → Create dashboard
   名稱: MyQuickDashboard
   ```

2. **新增第一個小部件 (數字顯示)**

   ```
   Add widget → Number
   Metric: AWS/EC2 → CPUUtilization (選擇任一實例)
   Statistic: Average
   Create widget
   ```

   > 💡 **如無 EC2 實例**：選擇 AWS/Lambda 的 Invocations 或 AWS/DynamoDB 的 ConsumedWriteCapacityUnits 替代

3. **新增第二個小部件 (線圖)**

   ```
   Add widget → Line
   同上指標配置
   Time range: Last 1 hour
   Create widget
   ```

4. **儲存儀表板**
   ```
   Save dashboard
   ```

### ✓ 驗證檢查

- [x] 儀表板已建立
- [x] 至少有 2 個小部件
- [x] 小部件能顯示資料或 INSUFFICIENT_DATA 狀態
- [x] 📸 **截圖：完整儀表板畫面（包含 2 個小部件）** (./screenshots/cloudwatch-prac-2.png)

---

## 練習 3: 建立和測試警報 (10分鐘)

### 目標

建立告警規則，理解警報狀態

### 操作步驟

1. **建立警報**

   ```
   Alarms → All alarms → Create alarm
   ```

2. **配置指標**

   ```
   Select metric
   → AWS/EC2 → CPUUtilization (選擇實例)
   → Statistic: Average
   → Period: 1 minute
   → Select metric
   ```

   > 💡 **如無 EC2 實例**：選擇其他可用指標，如 AWS/Lambda/Invocations 或 AWS/DynamoDB/ConsumedWriteCapacityUnits

3. **設定告警條件**

   ```
   Threshold: Greater than
   Value: 70 (%)
   Datapoints to alarm: 1 out of 1
   Next
   ```

4. **配置通知（重要）**

   ```
   Alarm state trigger: Select an SNS topic
   → Create new topic
   Topic name: cloudwatch-alerts
   Email list: 輸入你的郵箱（可選）
   Next
   ```

   > ⚠️ 注意：必須配置至少一個 SNS topic，否則警報會顯示 "No actions"，無法觸發通知
   >
   > 如不想配置郵件，可建立 topic 後跳過郵件確認步驟

5. **設定名稱**
   ```
   Alarm name: CPU-High-Alert
   Description: Alert when CPU > 70%
   Create alarm
   ```

### ✓ 驗證檢查

- [x] 警報已建立並在列表中可見
- [x] 能看到警報狀態 (OK/ALARM/INSUFFICIENT_DATA)
- [x] 警報的 **Actions 欄位顯示 SNS topic**，不是 "No actions"
- [x] 能編輯警報閾值
- [x] 📸 **截圖：警報列表（顯示 CPU-High-Alert 和 Actions）** (./screenshots/cloudwatch-prac-3.png)

---

## 練習 4: 建立自訂指標和日誌過濾 (7分鐘)

### 目標

從日誌建立自訂指標

### 操作步驟

1. **建立日誌群組**

   ```
   Logs → Log groups → Create log group
   名稱: /myapp/test
   Create
   ```

2. **建立日誌串流**

   ```
   進入日誌群組 /myapp/test
   Create log stream
   名稱: production
   ```

3. **建立指標過濾**

   ```
   日誌群組 → Actions → Create metric filter
   Filter name: ErrorFilter (必填)
   Filter pattern: [ERROR] 或 ERROR
   Next
   ```

   > ⚠️ Filter name 是必填的，AWS 需要用它來識別這個過濾規則

4. **配置指標**

   ```
   Metric namespace: MyApp
   Metric name: ErrorCount
   Metric value: 1
   Create metric filter
   ```

5. **新增測試日誌（關鍵步驟！）**

   指標過濾器需要實際的日誌資料才能產生指標，必須：

   ```
   日誌群組 → Log streams → production
   → Actions → Upload log events 或找到輸入框
   ```

   新增包含 "ERROR" 的日誌：

   ```
   [ERROR] Database connection failed
   [ERROR] Permission denied
   ERROR: Something went wrong
   ```

   > ⚠️ **重要**：如果日誌串流是空的，Metrics 中不會出現新指標！

6. **等待指標產生**
   ```
   提交日誌 → 等待 1-2 分鐘 → Metrics 中會出現 ErrorCount
   ```

### ✓ 驗證檢查

- [x] 日誌群組已建立
- [x] 日誌串流已建立
- [x] 指標過濾已建立
- [x] 能在 Metrics 中找到新指標
- [x] 📸 **截圖：指標過濾設定（Filter name 和 Pattern）** (./screenshots/cloudwatch-prac-4-1.png)
- [x] 📸 **截圖：Metrics 中出現新的 MyApp/ErrorCount 指標** (./screenshots/cloudwatch-prac-4-2.png)

---

## 練習 5: 基礎 Log Analytics 查詢 (可選，5分鐘)

### 目標

學會查詢和分析日誌

### 操作步驟

1. **打開 Log Analytics（原名 Insights）**

   ```
   CloudWatch 控制台
   → Logs (左側選單)
   → Log Analytics
   → Select log group: /myapp/test
   ```

2. **執行基礎查詢**

   ```sql
   fields @timestamp, @message
   | stats count() as total
   ```

3. **嘗試其他查詢**
   ```sql
   fields @timestamp, @message
   | filter @message like /ERROR/
   | limit 10
   ```

### ✓ 驗證檢查

- [x] 能執行查詢
- [x] 理解查詢結果結構
- [x] 📸 **截圖：第一個查詢的執行結果（統計日誌總數）** (./screenshots/cloudwatch-prac-5-1.png)
- [x] 📸 **截圖：第二個查詢的執行結果（篩選 ERROR 日誌）** (./screenshots/cloudwatch-prac-5-2.png)

---

## 快速參考

### CloudWatch 關鍵概念

| 概念              | 說明                                     |
| ----------------- | ---------------------------------------- |
| **Metrics**       | 指標資料點（CPU、記憶體等）              |
| **Namespace**     | 指標分類（AWS/EC2、AWS/Lambda等）        |
| **Dimensions**    | 指標的屬性（InstanceId、FunctionName等） |
| **Statistics**    | 統計方式（Average、Maximum、Minimum等）  |
| **Period**        | 資料聚合週期（60秒、300秒等）            |
| **Alarm**         | 基於指標的告警規則                       |
| **Log Group**     | 日誌的邏輯分組                           |
| **Log Stream**    | 日誌的實際流                             |
| **Metric Filter** | 從日誌提取指標                           |

### 常用閾值建議

| 指標               | 建議閾值   | 說明                           |
| ------------------ | ---------- | ------------------------------ |
| CPU Utilization    | > 70-80%   | 根據業務調整                   |
| Memory Utilization | > 80-85%   | 僅限有 CloudWatch Agent 的主機 |
| Disk Space         | < 10% 剩餘 | 儲存告急                       |
| Network In/Out     | 根據頻寬   | 檢測異常流量                   |

---

## SSH 連線 Ubuntu EC2（可選）

如需遠端連線到 EC2 實例進行測試或部署 CloudWatch Agent：

```bash
# 基礎連線命令
ssh -i cloudwatch-test-key.pem ubuntu@<EC2-Public-IP>

# 示例
ssh -i cloudwatch-test-key.pem ubuntu@54.123.45.67

# 使用 DNS 名稱
ssh -i cloudwatch-test-key.pem ubuntu@ec2-54-123-45-67.compute-1.amazonaws.com
```

**取得公網 IP 的方法：**

1. **AWS Console**: EC2 → Instances → 點擊實例 → 查看 "Public IPv4 address"
2. **AWS CLI**:
   ```bash
   aws ec2 describe-instances --query 'Reservations[0].Instances[0].PublicIpAddress'
   ```

**常見 SSH 錯誤排查：**

- `Permission denied (publickey)` - 檢查密鑰檔案權限: `chmod 600 cloudwatch-test-key.pem`
- `Connection refused` - 檢查實例狀態是否為 "Running"
- `Connection timed out` - 檢查安全群組是否允許 SSH (22端口)

---

## 清理資源（完成後）

為避免 AWS 費用，完成練習後建議清理：

```bash
# 刪除建立的資源
1. Dashboards → MyQuickDashboard → Delete dashboard
2. Alarms → CPU-High-Alert → Delete alarm
3. Logs → Log groups → /myapp/test → Delete log group
```

---

## 後續學習路徑

- [ ] CloudWatch Events 和 EventBridge
- [ ] CloudWatch Agent 部署
- [ ] Anomaly Detector（異常檢測）
- [ ] 使用 Log Analytics（原 CloudWatch Insights）進行進階查詢
- [ ] 使用 CloudFormation 自動化配置
- [ ] CloudWatch 整合 SNS/SQS

---

**⏱️ 預計完成時間：30 分鐘**  
**📚 難度：初級**  
**✅ 最後更新：2026-10-07**

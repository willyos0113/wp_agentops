# 簡報實作步驟

---

## 目的

將簡報 `OUTLINE.md` 中所需的截圖 `screenshotN.png`(N 從 1~11)，以 AWS 服務操作步驟，安排一系列的操作步驟，目的使本專案使用者能快速重現 `OUTLINE.md` 的內容。

## 截圖總覽

截圖存放於 `slides/screenshots/`，檔名與 `OUTLINE.md` 的編號對應。

| 截圖             | 簡報頁 | 內容                                          | 取得階段 |
| ---------------- | ------ | --------------------------------------------- | -------- |
| screenshot2      | p8     | Pricing Calculator 試算結果（價格出處）       | 部署前   |
| screenshot1      | p3     | 正常狀態的 WordPress 首頁                     | 部署後   |
| screenshot3      | p9     | RDS `Internet access gateway: Disabled`       | 部署後   |
| screenshot11     | p12    | `AIOpsAssistantPolicy` 唯讀政策               | 部署後   |
| screenshot4 ~ 6  | p10    | 故障演練 ① ~ ③：移除規則、回 500、Alarm       | 故障演練 |
| screenshot7 ~ 10 | p11    | 故障演練 ④a ~ ⑥：告警信、根因報告、還原、恢復 | 故障演練 |

## 步驟

部署、演練與清理的完整指令見 [README.md](../README.md) 的「檢核點驗證步驟」，以下只標出每張截圖該在哪個時間點、從哪裡取得。以下指令都在 `infra/` 目錄下執行，region 為 `ap-northeast-1`。

### 一、部署前

1. **screenshot2**（p8，價格出處）：開啟 AWS Pricing Calculator，Region 選 Asia Pacific (Tokyo)，分別估算：
   - Amazon RDS for MySQL：`db.t3.micro`、20 GB、Single-AZ，預期約 21.74 USD / 月。
   - Amazon EC2：`t3.micro`，預期約 9.93 USD / 月。
   - 截圖需同時看得到服務、規格與月費。若當下試算與大綱數字不同，以大綱為準，並回頭確認是規格填錯還是價格已調整。
   - 簡報只比較 EC2 與 RDS 這兩項，ALB 等其他項目不必放進這次試算。

### 二、部署後、故障演練前

1. 依 [README.md](../README.md) 的「[P0-2 檢核點驗證步驟 > 部署](../README.md#部署)」與「[P1-2 檢核點驗證步驟 > 部署](../README.md#部署-1)」完成 `terraform apply`、SNS 訂閱確認與 WordPress 安裝。部署後 ALB 會先回 `502 Bad Gateway`，等 target group `tg-yiweee-web` 的 target 轉為 `healthy` 再開始截圖。
2. **screenshot1**（p3，正常狀態首頁）：用瀏覽器開啟 `terraform output -raw wordpress_url`（HTTPS 網域），截下 WordPress 商店首頁。
3. **screenshot3**（p9，DB 不對外）：到 RDS console，開啟 `rds-yiweee`，在連線資訊的「Connect using」選 Code snippets，截下 `Internet access gateway: Disabled` 這一行。
4. **screenshot11**（p12，權限唯讀）：到 IAM > Roles > `role-yiweee-investigation` > Permissions，開啟受管政策 `AIOpsAssistantPolicy`，截下政策說明的 `Provides ReadOnly permissions` 與 Action 清單。

### 三、故障演練

依 [README.md](../README.md) 的「[P1-2 檢核點驗證步驟 > 演練前確認](../README.md#演練前確認)」確認網站回 `200`、Alarm 為 `INSUFFICIENT_DATA` 後開始。演練期間隨手記下各步驟的時間，p10 的「約 2 分鐘」（故障到收到告警信）要用。

演練時的注意事項：

- 請求經 ALB 進來，ALB 每 30 秒的健康檢查也會進 Apache access log，故障期間可能在你發出請求前就觸發 Alarm。以步驟 ① 記下的時間為「故障起點」，不要用 Alarm 轉為 `ALARM` 的時間倒推。
- 每次請求約等 60 秒才回 `500`（ALB idle timeout 已調為 120 秒，不會先回 504），別中途中斷 `curl`。
- ④b 的調查要等數分鐘才完成，可在等待期間先處理 ④a 的截圖。

| 步驟 | 操作                                                                                                                                                                                                                           | 截圖                                                                                                |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| ①    | 移除 DB SG 的 3306 規則，並記下時間<br>macOS：`eval "$(terraform output -raw fault_inject_command)"`<br>Windows（PowerShell）：`Invoke-Expression (terraform output -raw fault_inject_command)`                                | **screenshot4**：終端機輸出，看得到被移除的規則（`FromPort` / `ToPort` 為 3306）                    |
| ②    | 發出請求，每次約等 60 秒，預期回 `500`<br>macOS：`eval "$(terraform output -raw fault_probe_command)"`<br>Windows（PowerShell）：`curl.exe -s -o NUL -w '%{http_code}\n' --max-time 300 (terraform output -raw wordpress_url)` | **screenshot5**：終端機的 `curl` 狀態碼 `500`                                                       |
| ③    | 到 CloudWatch > Alarms 開啟 `alarm-yiweee-http-5xx`，等它轉為 `ALARM`（也可在 Dashboard 同步觀察）                                                                                                                             | **screenshot6**：Alarm 狀態為 `ALARM`，含 5xx 指標飆高的圖，只截上半部有內容的區域                  |
| ④a   | 到信箱開啟 AWS Notifications 寄來的告警信，並記下收信時間                                                                                                                                                                      | **screenshot7**：5xx 告警信                                                                         |
| ④b   | 到 CloudWatch > investigations，開啟由 Alarm 自動建立的調查，等調查完成                                                                                                                                                        | **screenshot8**：調查結果中的根因假設（Hypotheses）段落，需看得到 `RevokeSecurityGroupIngress` 事件 |
| ⑤    | 執行 `terraform apply` 還原 3306 規則                                                                                                                                                                                          | **screenshot9**：終端機輸出，看得到 DB SG 的 3306 規則被加回                                        |
| ⑥    | 再執行一次 ② 的指令，預期回 `200`，並用瀏覽器重新整理首頁                                                                                                                                                                      | **screenshot10**：網站恢復正常的畫面                                                                |

p10 的偵測時間卡片（`12:17 移除規則 → 12:19 收到告警信`）以步驟 ① 與 ④a 記下的時間為準，時間不同時要回頭更新簡報與 `OUTLINE.md`。

### 四、收尾

1. 截圖含網域、信箱與 AWS 帳號 ID，放進簡報或公開前先遮蔽。
2. 依 [README.md](../README.md) 的「[P1-2 檢核點驗證步驟 > 清理](../README.md#清理)」先封存 investigations，再執行 `terraform destroy`。

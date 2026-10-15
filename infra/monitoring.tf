# ========================================
# Terraform Monitoring Resource Configuration
# ========================================

# === 資料流流程 ===
# [ Apache ]
#        │
#        ▼ (寫入本機 access.log / error.log)
# [ CloudWatch Agent ] ──► (本檔之外，設定見 user_data.sh)
#        │
#        ▼ (讀取本機日誌，送進 Log group)
# [ aws_cloudwatch_log_group ] ──► (apache_error：只保存，供調查時查閱)
#        │
#        ▼ (apache_access：挑出 5xx & 轉換成 Metric)
# [ aws_cloudwatch_log_metric_filter ]
#        │
#        ▼ (每 60 秒加總 Metric，>= 1 就觸發)
# [ aws_cloudwatch_metric_alarm ] ──► [ awscc_aiops_investigation_group ] (自動調查，定義在 agent.tf)
#        │
#        ▼ (觸發告警 Notification)
# [ aws_sns_topic ]
#        │
#        ▼ (轉發給訂閱者)
# [ aws_sns_topic_subscription ] ──► (寄信給維護人員)
#
# [ aws_cloudwatch_dashboard ] ──► (把 Metric、Alarm 狀態、日誌、EC2 指標集中在一個畫面，供人工查看)

# === 觀測：Web server 的 Apache 日誌(意義：log 容器) ===
resource "aws_cloudwatch_log_group" "apache_access" { # Apache access log（由 CloudWatch Agent 寫入）
  name              = "/yiweee/web/apache/access"
  retention_in_days = var.log_retention_days # 設定保留天數，避免日誌（含訪客 IP）無限累積

  tags = {
    Name = "log-yiweee-apache-access"
  }
}

resource "aws_cloudwatch_log_group" "apache_error" { # Apache error log（由 CloudWatch Agent 寫入）
  name              = "/yiweee/web/apache/error"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "log-yiweee-apache-error"
  }
}

# === 偵測：HTTP 5xx 轉成指標(意義：log metric filter) ===
resource "aws_cloudwatch_log_metric_filter" "http_5xx" { # 從 access log 中挑出狀態碼為 5xx 的請求，每筆計為 1
  name           = "mf-yiweee-http-5xx"
  log_group_name = aws_cloudwatch_log_group.apache_access.name
  pattern        = "[ip, ident, user, timestamp, request, status=5*, ...]" # 對應 Apache combined 格式的前六個欄位

  metric_transformation {
    name      = "Http5xxCount"
    namespace = "yiweee/WordPress"
    value     = "1"
    unit      = "Count"
    # 不設 default_value：沒有請求時指標沒有資料，Alarm 會是 INSUFFICIENT_DATA（預期狀態）
  }
}

# === 偵測：告警信通知(意義：SNS topic) ===
resource "aws_sns_topic" "alarm" { # Alarm 觸發時發送通知的 SNS topic
  name = "sns-yiweee-alarm"

  tags = {
    Name = "sns-yiweee-alarm"
  }
}

resource "aws_sns_topic_subscription" "alarm_email" { # 訂閱者為維護人員信箱，建立後需人工點擊確認信
  topic_arn = aws_sns_topic.alarm.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# === 偵測：HTTP 5xx Alarm(意義：log metric alarm) ===
resource "aws_cloudwatch_metric_alarm" "http_5xx" { # 1 分鐘內出現 1 筆 5xx 即觸發
  alarm_name        = "alarm-yiweee-http-5xx"
  alarm_description = "WordPress 回應 HTTP 5xx。CloudWatch investigations 已自動開始調查，請至 CloudWatch console（https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}）左側選單 AI Operations > Investigations 查看調查結果。"

  namespace           = aws_cloudwatch_log_metric_filter.http_5xx.metric_transformation[0].namespace
  metric_name         = aws_cloudwatch_log_metric_filter.http_5xx.metric_transformation[0].name
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1 # 故障情境下每個請求都要等到逾時才產生一筆 500，門檻要低到零星幾筆就觸發
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "missing"

  alarm_actions = [                             # 兩個 action 平行進行
    awscc_aiops_investigation_group.yiweee.arn, # 啟動 CloudWatch investigations 調查（判讀）
    aws_sns_topic.alarm.arn                     # 寄告警信給維護人員
  ]

  tags = {
    Name = "alarm-yiweee-http-5xx"
  }
}

# === 視覺化：Dashboard(意義：集中查看的畫面，不參與告警與調查) ===
resource "aws_cloudwatch_dashboard" "yiweee" { # 一個畫面看 5xx 趨勢、Alarm 狀態、最新日誌與 EC2 負載
  dashboard_name = "dashboard-yiweee-wordpress"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric" # HTTP 5xx 次數趨勢（來自 metric filter）
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "HTTP 5xx count"
          region  = var.aws_region
          view    = "timeSeries"
          stat    = "Sum"
          period  = 60
          metrics = [[aws_cloudwatch_log_metric_filter.http_5xx.metric_transformation[0].namespace, aws_cloudwatch_log_metric_filter.http_5xx.metric_transformation[0].name]]
        }
      },
      {
        type   = "alarm" # Alarm 目前狀態
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Alarm status"
          alarms = [aws_cloudwatch_metric_alarm.http_5xx.arn]
        }
      },
      {
        type   = "metric" # EC2 CPU
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "EC2 CPUUtilization"
          region  = var.aws_region
          view    = "timeSeries"
          stat    = "Average"
          period  = 60
          metrics = [["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.web.id]]
        }
      },
      {
        type   = "metric" # EC2 網路流量
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "EC2 Network In/Out"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.web.id],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.web.id]
          ]
        }
      },
      {
        type   = "log" # access log 中最近的 5xx 請求
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          title  = "Recent 5xx requests (access log)"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.apache_access.name}' | fields @timestamp, @message | filter @message like / 5\\d\\d / | sort @timestamp desc | limit 20"
        }
      },
      {
        type   = "log" # error log 最新紀錄
        x      = 0
        y      = 18
        width  = 24
        height = 6
        properties = {
          title  = "Latest Apache errors (error log)"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.apache_error.name}' | fields @timestamp, @message | sort @timestamp desc | limit 20"
        }
      }
    ]
  })
}

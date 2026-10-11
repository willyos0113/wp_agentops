# ========================================
# Terraform Monitoring Agent Configuration
# ========================================

# === 資源關係流程（各資源如何組成 Investigation group）===
# [ data.aws_caller_identity ] ──► (提供帳號 ID，用來限制下方兩處 policy 只接受本帳號)
#
# [ aws_iam_role ] ◄── [ aws_iam_role_policy_attachment ] (附加唯讀政策 AIOpsAssistantPolicy)
#        │
#        ▼ (先經過 time_sleep 等 30 秒，讓 Role 生效)
#        ▼ (調查時以這個 Role 的身分讀取日誌、指標、CloudTrail)
# [ awscc_aiops_investigation_group ]
#        ▲
#        │ (Alarm 觸發時建立調查，由 investigation_group_policy 放行)
# [ aws_cloudwatch_metric_alarm ] (定義在 monitoring.tf)

# === 維運 Agent：CloudWatch investigations ===
data "aws_caller_identity" "current" {} # 取得目前的 AWS 帳號 ID，用於限制 role 與 policy 的來源

# === 調查用的 IAM Role（唯讀）===
resource "aws_iam_role" "investigation" { # 由 CloudWatch investigations（aiops.amazonaws.com）擔任的 Role
  name = "role-yiweee-investigation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "aiops.amazonaws.com"
      }
      Condition = { # 只允許本帳號、本 region 的 investigation group 擔任
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:aiops:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
        }
      }
    }]
  })

  tags = {
    Name = "role-yiweee-investigation"
  }
}

resource "aws_iam_role_policy_attachment" "investigation_readonly" { # 只有唯讀權限（讀日誌、指標、CloudTrail 等），不能修改資源
  role       = aws_iam_role.investigation.name
  policy_arn = "arn:aws:iam::aws:policy/AIOpsAssistantPolicy"
}

resource "time_sleep" "investigation_role_propagation" { # IAM Role 建好後要幾秒才會在各服務生效，太早使用會讓 investigation group 建立失敗
  create_duration = "30s"

  depends_on = [aws_iam_role_policy_attachment.investigation_readonly]
}

# === Investigation group ===
resource "awscc_aiops_investigation_group" "yiweee" { # 每個帳號在同一 region 只能有一個 investigation group
  name                                 = "ig-yiweee"
  role_arn                             = aws_iam_role.investigation.arn
  retention_in_days                    = 90
  is_cloud_trail_event_history_enabled = true        # 讓調查能讀 CloudTrail 的變更紀錄（如 SG 規則被移除）
  tag_key_boundaries                   = ["Project"] # 帳號內有其他專案的資源，用 Project 標籤（provider.tf 的 default_tags）縮小調查範圍

  investigation_group_policy = jsonencode({ # 允許本帳號的 CloudWatch Alarm 建立調查
    Version = "2008-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "aiops.alarms.cloudwatch.amazonaws.com"
      }
      Action = [
        "aiops:CreateInvestigation",
        "aiops:CreateInvestigationEvent"
      ]
      Resource = "*"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:*"
        }
      }
    }]
  })

  tags = [
    {
      key   = "Name"
      value = "ig-yiweee"
    },
    { # awscc provider 沒有 default_tags，需自行補上
      key   = "Project"
      value = "yiweee"
    }
  ]

  depends_on = [time_sleep.investigation_role_propagation]
}

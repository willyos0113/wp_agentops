# ========================================
# Terraform Provider Configuration
# ========================================

# === 設定關係流程（本檔沒有資源，只決定 Terraform 用哪些外掛連到哪裡）===
# [ terraform.required_providers ] (宣告需要的 provider 外掛與版本)
#        │
#        ▼ (terraform init 時下載)
# [ aws ] ──► (負責 aws_* 資源：本專案絕大多數的 AWS 資源)
# [ awscc ] ──► (負責 awscc_* 資源：agent.tf 的 investigation group)
# [ time ] ──► (負責 time_sleep：agent.tf 等待 IAM Role 生效)
# [ cloudflare ] ──► (負責 cloudflare_record：alb.tf 建立 ACM 驗證與網站的 DNS 記錄)
#
# [ provider "aws" / provider "awscc" ] ──► (設定 region 與 profile，決定連到哪個帳號的哪個區域)
# [ provider "cloudflare" ] ──► (以 API token 連到 Cloudflare，token 來自 tfvars)
# [ provider "aws" 的 default_tags ] ──► (替所有 aws_* 資源加上 Project 標籤)
# time 只在本機運作，不需要 provider 區塊

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    awscc = { # aws provider 尚未支援 CloudWatch investigations，改用 Cloud Control 版本
      source  = "hashicorp/awscc"
      version = "~> 1.0"
    }
    time = { # 用 time_sleep 等待 IAM Role 生效
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
    cloudflare = { # 網域的 DNS 在 Cloudflare，用來建立 ACM 的 DNS 驗證記錄與指向 ALB 的記錄
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.profile

  default_tags { # 所有 aws_* 資源都帶上 Project 標籤，讓 CloudWatch investigations 辨識哪些資源屬於同一個系統（見 agent.tf）
    tags = {
      Project = "yiweee"
    }
  }
}

provider "awscc" {
  region  = var.aws_region
  profile = var.profile
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

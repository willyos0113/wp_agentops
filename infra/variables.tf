# ========================================
# Terraform Variables Configuration
# ========================================

# === 變數關係流程（本檔沒有資源，只宣告其他檔案會用到的輸入值）===
# [ terraform.tfvars ] (實際的值，不進版控；範本見 terraform.tfvars.example)
#        │
#        ▼ (terraform plan / apply 時讀入；沒給值的變數使用 default，沒有 default 的必須提供)
# [ variable ]
#        │
#        ▼ (各 .tf 檔以 var.<名稱> 引用)
# [ 各 .tf 檔的資源 ]
#
# 依用途分組：
# [ 連線設定 ] ──► (provider.tf：連到哪個 region、用哪個 AWS CLI profile)
# [ 網路設定 ] ──► (network.tf：VPC 與 subnet 的 CIDR)
# [ 網域與 HTTPS 設定 ] ──► (alb.tf：網域名稱、Cloudflare API token)
# [ EC2 / RDS 設定 ] ──► (compute.tf：機型、儲存空間、兩組資料庫密碼)
# [ 監控與告警設定 ] ──► (monitoring.tf：告警信箱、日誌保留天數)

# === 連線設定值 ===
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "profile" {
  description = "AWS CLI profile name"
  type        = string
  default     = "course"
}

# === 網路設定值 ===
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet (1a)"
  type        = string
}

variable "public_subnet_1c_cidr" {
  description = "CIDR block for public subnet (1c, for the ALB)"
  type        = string
}

variable "private_subnet_1a_cidr" {
  description = "CIDR block for private subnet (1a)"
  type        = string
}

variable "private_subnet_1c_cidr" {
  description = "CIDR block for private subnet (1c)"
  type        = string
}

# === EC2 設定值 ===
variable "instance_type" {
  description = "EC2 instance type for WordPress"
  type        = string
  default     = "t3.micro"
}

# === RDS MySQL 設定值 ===
variable "db_master_password" {
  description = "Master password for RDS MySQL"
  type        = string
  sensitive   = true
}

variable "db_wp_password" {
  description = "Password for WordPress database user"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_storage_size" {
  description = "Allocated storage for RDS (GB)"
  type        = number
  default     = 20
}

# === 網域與 HTTPS 設定值 ===
variable "domain_name" {
  description = "Domain name served by the ALB (the Cloudflare zone, e.g. example.com)"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:Read and DNS:Edit on the domain"
  type        = string
  sensitive   = true
}

# === 監控與告警設定值 ===
variable "alarm_email" {
  description = "Email address that receives alarm notifications (SNS subscription must be confirmed manually)"
  type        = string
}

variable "log_retention_days" {
  description = "Retention in days for the Apache log groups"
  type        = number
  default     = 14
}

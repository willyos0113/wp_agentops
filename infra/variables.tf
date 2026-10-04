# === 網路設定值 ===
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet (1a)"
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

variable "profile" {
  description = "AWS CLI profile name"
  type        = string
  default     = "course"
}

variable "admin_cidr" {
  description = "Admin's public IP in CIDR format, e.g. 203.0.113.10/32"
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
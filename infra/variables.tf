variable "default_vpc_id" {
  description = "the default vpc id when inital the aws"
  default     = "vpc-0fc5ec326688850f6"
}

variable "admin_cidr" {
  description = "the admin public ip in cidr format, e.g. 203.0.113.10/32"
  type        = string
}

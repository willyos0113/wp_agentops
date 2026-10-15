# ========================================
# Terraform Outputs Configuration
# ========================================

# === 輸出關係流程（本檔沒有資源，只把其他檔案的資源屬性印出來）===
# [ 各 .tf 檔的資源 ]
#        │
#        ▼ (terraform apply 完成後才有實際值)
# [ output ]
#        │
#        ▼ (印在終端機；之後可用 terraform output 再查)
# [ 使用者 ]
#
# 依來源分組：
# [ network.tf ] ──► (VPC ID、三個 subnet ID、web 與 db 的 security group ID)
# [ compute.tf ] ──► (EC2 的 ID 與 IP、RDS 的位址與資料庫名稱、key pair 名稱、私鑰檔路徑)
# [ monitoring.tf ] ──► (兩個 log group 名稱、alarm 名稱、SNS topic ARN、dashboard 網址)
# [ agent.tf ] ──► (investigation group ARN)
#
# 組合成可直接複製使用的字串：
# [ wordpress_url ] ──► (用瀏覽器開啟 WordPress)
# [ ssh_command ] ──► (SSH 登入 EC2)
# [ fault_inject_command ] ──► (移除 db SG 的 3306 規則，重現「DB 連不上」的故障)
# [ fault_probe_command ] ──► (送出請求並印出 HTTP 狀態碼，確認故障是否發生)

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.yiweee.id
}

output "public_subnet_id" {
  description = "The ID of the public subnet (1a)"
  value       = aws_subnet.public_1a.id
}

output "private_subnet_1a_id" {
  description = "The ID of the private subnet (1a)"
  value       = aws_subnet.private_1a.id
}

output "private_subnet_1c_id" {
  description = "The ID of the private subnet (1c)"
  value       = aws_subnet.private_1c.id
}

output "web_ec2_id" {
  description = "The ID of the WordPress EC2 instance"
  value       = aws_instance.web.id
}

output "web_ec2_public_ip" {
  description = "The public IP address of the WordPress EC2"
  value       = aws_instance.web.public_ip
}

output "web_ec2_private_ip" {
  description = "The private IP address of the WordPress EC2"
  value       = aws_instance.web.private_ip
}

output "web_sg_id" {
  description = "The ID of the web server security group"
  value       = aws_security_group.web.id
}

output "db_sg_id" {
  description = "The ID of the database security group"
  value       = aws_security_group.db.id
}

output "db_endpoint" {
  description = "The endpoint of the RDS MySQL instance"
  value       = aws_db_instance.yiweee.endpoint
}

output "db_address" {
  description = "The address of the RDS MySQL instance (without port)"
  value       = aws_db_instance.yiweee.address
}

output "db_name" {
  description = "The database name"
  value       = aws_db_instance.yiweee.db_name
}

output "key_pair_name" {
  description = "The name of the key pair for SSH access"
  value       = aws_key_pair.yiweee.key_name
}

output "private_key_file" {
  description = "The path to the private key file"
  value       = local_file.yiweee_key.filename
  sensitive   = true
}

output "wordpress_url" {
  description = "URL to access WordPress"
  value       = "http://${aws_instance.web.public_ip}"
}

output "ssh_command" {
  description = "SSH command to connect to the web server"
  value       = "ssh -i ${local_file.yiweee_key.filename} ubuntu@${aws_instance.web.public_ip}"
}

output "apache_access_log_group" {
  description = "CloudWatch log group for the Apache access log"
  value       = aws_cloudwatch_log_group.apache_access.name
}

output "apache_error_log_group" {
  description = "CloudWatch log group for the Apache error log"
  value       = aws_cloudwatch_log_group.apache_error.name
}

output "http_5xx_alarm_name" {
  description = "The name of the HTTP 5xx alarm"
  value       = aws_cloudwatch_metric_alarm.http_5xx.alarm_name
}

output "alarm_sns_topic_arn" {
  description = "The ARN of the SNS topic for alarm notifications"
  value       = aws_sns_topic.alarm.arn
}

output "investigation_group_arn" {
  description = "The ARN of the CloudWatch investigations investigation group"
  value       = awscc_aiops_investigation_group.yiweee.arn
}

output "fault_inject_command" {
  description = "Command to reproduce the 'DB unreachable' scenario (restore with terraform apply)"
  value       = "aws ec2 revoke-security-group-ingress --group-id ${aws_security_group.db.id} --protocol tcp --port 3306 --source-group ${aws_security_group.web.id} --region ${var.aws_region} --profile ${var.profile}"
}

output "fault_probe_command" {
  description = "Command to send a request and print the HTTP status code (timeout longer than WordPress DB wait)"
  value       = "curl -s -o /dev/null -w '%%{http_code}\\n' --max-time 300 http://${aws_instance.web.public_ip}/"
}

output "dashboard_url" {
  description = "The URL of the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.yiweee.dashboard_name}"
}

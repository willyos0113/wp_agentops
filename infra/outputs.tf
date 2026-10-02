output "instance_id" {
  description = "The ID of the GitLab EC2 instance"
  value       = aws_instance.gitlab.id
}

output "instance_public_ip" {
  description = "The public IP address of the GitLab instance"
  value       = aws_instance.gitlab.public_ip
}

output "instance_private_ip" {
  description = "The private IP address of the GitLab instance"
  value       = aws_instance.gitlab.private_ip
}

output "security_group_id" {
  description = "The ID of the GitLab security group"
  value       = aws_security_group.gitlab.id
}

output "key_pair_name" {
  description = "The name of the key pair for SSH access"
  value       = aws_key_pair.gitlab.key_name
}

output "private_key_file" {
  description = "The path to the private key file"
  value       = local_file.gitlab.filename
  sensitive   = true
}

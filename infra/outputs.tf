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

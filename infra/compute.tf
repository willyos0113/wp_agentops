# TLS 私鑰和 AWS key pair
resource "tls_private_key" "gitlab" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "gitlab" {
  key_name   = "gitlab"
  public_key = tls_private_key.gitlab.public_key_openssh
}

# 本地文件以儲存私鑰
resource "local_file" "gitlab" {
  content  = tls_private_key.gitlab.private_key_pem
  filename = format("%s.pem", aws_key_pair.gitlab.key_name)
}

# 選擇最新的 Ubuntu 20.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# EC2 實例
resource "aws_instance" "gitlab" {
  ami                     = data.aws_ami.ubuntu.id
  instance_type           = "t3.micro"
  subnet_id               = sort(data.aws_subnets.subnet_ids.ids)[0]
  key_name                = aws_key_pair.gitlab.key_name
  vpc_security_group_ids  = [aws_security_group.gitlab.id]
  disable_api_termination = false
  ebs_optimized           = true
  hibernation             = false

  tags = {
    Name    = "Gitlab Server"
    Usage   = "For SCM"
    Creator = "Terraform"
  }

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = 30
    volume_type           = "gp3"
    throughput            = 125
    iops                  = 3000
    tags = {
      Name     = "Gitlab Server"
      Attached = "Gitlab Server"
    }
  }
}

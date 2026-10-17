# ========================================
# Terraform Compute Resource Configuration
# ========================================

# === 資源關係流程（各資源如何組成 EC2）===
# 金鑰：
# [ tls_private_key ] ──► [ local_file ] (私鑰存成本機 yiweee.pem)
#        │
#        ▼ (公鑰上傳到 AWS)
# [ aws_key_pair ] ──► (給 EC2：SSH 登入金鑰)
#
# 權限：
# [ aws_iam_role ] ◄── [ aws_iam_role_policy_attachment ] (ssm_access、cloudwatch_agent：把政策附加到 Role)
#        │
#        ▼ (把 Role 包裝成 EC2 可掛載的形式)
# [ aws_iam_instance_profile ] ──► (給 EC2：SSM 連線與寫入日誌的權限)
#
# 資料庫：
# [ aws_db_subnet_group ]
#        │
#        ▼ (指定 RDS 可放置的 private subnet)
# [ aws_db_instance ] ──► (給 EC2：資料庫位址與名稱，寫進 user_data.sh)
#
# 映像檔與日誌：
# [ data.aws_ami ] ──► (給 EC2：最新的 Ubuntu 22.04 映像檔 ID)
# [ aws_cloudwatch_log_group ] ──► (給 EC2：log group 名稱，寫進 user_data.sh，定義在 monitoring.tf)
#
# 主機：
# [ aws_instance ] (收齊以上各項後建立，開機時執行 user_data.sh)
#        │
#        ▼ (執行期：WordPress 讀寫資料)
# [ aws_db_instance ]

# === EC2 SSH 金鑰對 ===
resource "tls_private_key" "yiweee" { # 生成一個 4096 位元的 RSA 私鑰
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "yiweee" { # 將 tls_private_key 生成的公鑰上傳到 AWS，建立一個 Key Pair
  key_name   = "yiweee"
  public_key = tls_private_key.yiweee.public_key_openssh
}

resource "local_file" "yiweee_key" { # 將 tls_private_key 生成的私鑰寫入本地檔案
  content              = tls_private_key.yiweee.private_key_pem
  filename             = "${path.module}/yiweee.pem"
  file_permission      = "0600"
  directory_permission = "0700"
}

# === 取得 Ubuntu AMI ===
data "aws_ami" "ubuntu" { # 取得最新的 Ubuntu 22.04 LTS AMI
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}


# === EC2 instance 設定 ===
resource "aws_instance" "web" { # 建立 WordPress EC2 instance
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_1a.id
  key_name               = aws_key_pair.yiweee.key_name
  vpc_security_group_ids = [aws_security_group.web.id]
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    db_name            = aws_db_instance.yiweee.db_name
    db_user            = "wp"
    db_password        = var.db_wp_password
    db_master_password = var.db_master_password
    db_host            = aws_db_instance.yiweee.address
    domain_name        = var.domain_name
    access_log_group   = aws_cloudwatch_log_group.apache_access.name
    error_log_group    = aws_cloudwatch_log_group.apache_error.name
  }))                                                      # 傳送給 aws 腳本，記得用 base64 編碼，確保特殊字元在 protocol 解析文本時不會被破壞
  iam_instance_profile = aws_iam_instance_profile.web.name # 讓 EC2 可以使用 IAM Role 

  root_block_device { # 設定 EC2 的根磁碟
    delete_on_termination = true
    volume_size           = 20
    volume_type           = "gp3"
    tags = {
      Name = "ec2-yiweee-root"
    }
  }

  tags = {
    Name = "ec2-yiweee"
  }

  depends_on = [
    aws_db_instance.yiweee,                         # 確保 RDS MySQL 建立後再創建 EC2
    aws_iam_role_policy_attachment.ssm_access,      # 確保 IAM Role 的 SSM 建立後再創建 EC2
    aws_iam_role_policy_attachment.cloudwatch_agent # 確保 IAM Role 的 CloudWatch Agent 建立後再創建 EC2
  ]
}

# === IAM Role 與 Instance Profile 設定 ===
resource "aws_iam_role" "web" { # 建立一個 IAM Role，讓 EC2 可以使用 SSM 連線、把日誌寫入 CloudWatch Logs
  name = "role-yiweee-web"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "role-yiweee-web"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_access" { # 將 SSM 政策附加到 IAM Role 上，讓 EC2 可以使用 SSM 連線
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" { # 讓 EC2 上的 CloudWatch Agent 可以把日誌寫入 CloudWatch Logs
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "web" { # 建立一個 IAM Instance Profile，讓 EC2 可以使用 IAM Role 
  name = "profile-yiweee-web"
  role = aws_iam_role.web.name
}

# === RDS MySQL 設定 ===
resource "aws_db_subnet_group" "yiweee" { # RDS 預設需要一個 DB Subnet Group(這裡引用 pri_1a 與 pri_1c 兩個 private subnet)
  name       = "dbsg-yiweee"
  subnet_ids = [aws_subnet.private_1a.id, aws_subnet.private_1c.id]

  tags = {
    Name = "dbsg-yiweee"
  }
}

resource "aws_db_instance" "yiweee" { # 建立一個 RDS MySQL instance
  identifier             = "rds-yiweee"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_storage_size
  db_subnet_group_name   = aws_db_subnet_group.yiweee.name
  vpc_security_group_ids = [aws_security_group.db.id]
  db_name                = "wordpress" # 建立一個名為 wordpress 的資料庫
  username               = "master"    # DB 的 master 帳號
  password               = var.db_master_password
  availability_zone      = "${var.aws_region}a" # RDS 放於 private subnet 1a(另一個預留，但不使用)
  publicly_accessible    = false
  skip_final_snapshot    = true # 刪除 RDS 時不保留 snapshot
  multi_az               = false

  tags = {
    Name = "rds-yiweee"
  }
}

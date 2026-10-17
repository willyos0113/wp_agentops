# ========================================
# Terraform Network Configuration
# ========================================

# === 網路流量流程（以下資源全部建在 aws_vpc 這個容器內）===
# [ Internet ]
#        │
#        ▼
# [ aws_internet_gateway ] (VPC 對外的出入口)
#        │
#        ▼ (aws_route_table.public：0.0.0.0/0 指向 IGW)
# [ aws_subnet.public_1a / public_1c ] (放 ALB；EC2 只在 1a)
#        │
#        ▼ (aws_security_group.alb：放行 HTTP 80 與 HTTPS 443)
# [ ALB ] (定義在 alb.tf)
#        │
#        ▼ (aws_security_group.web：只放行來自 ALB SG 的 HTTP 80、管理者 IP 的 SSH 22)
# [ EC2 ] (定義在 compute.tf)
#        │
#        ▼ (aws_security_group.db：只放行來自 web SG 的 MySQL 3306)
# [ aws_subnet.private_1a / private_1c ] (放 RDS，實際在 1a；aws_route_table.private 只有 VPC 內部路由，不通外網)
#
# 兩種「綁定用」的資源：
# [ aws_route_table_association ] ──► (把 route table 綁到 subnet)
# [ aws_security_group_rule ] ──► (把放行規則掛到 security group；SG 本身只是空殼)

# === 設定 VPC 內部網路區塊 ===
resource "aws_vpc" "yiweee" { # 建立一個 VPC
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "vpc-yiweee"
  }
}

resource "aws_internet_gateway" "yiweee" { # 綁定 Internet Gateway 到 VPC
  vpc_id = aws_vpc.yiweee.id

  tags = {
    Name = "igw-yiweee"
  }
}

resource "aws_subnet" "public_1a" { # 建立一個 Public Subnet(1a)，並綁定到 VPC
  vpc_id                  = aws_vpc.yiweee.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-yiweee-public-1a"
  }
}

resource "aws_subnet" "public_1c" { # 建立第二個 Public Subnet(1c)，ALB 必須橫跨兩個 AZ；EC2 不放這裡
  vpc_id                  = aws_vpc.yiweee.id
  cidr_block              = var.public_subnet_1c_cidr
  availability_zone       = "${var.aws_region}c"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-yiweee-public-1c"
  }
}

resource "aws_subnet" "private_1a" { # 建立二個 Private Subnet(1a, 1c)，並綁定到 VPC
  vpc_id            = aws_vpc.yiweee.id
  cidr_block        = var.private_subnet_1a_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "subnet-yiweee-private-1a"
  }
}

resource "aws_subnet" "private_1c" {
  vpc_id            = aws_vpc.yiweee.id
  cidr_block        = var.private_subnet_1c_cidr
  availability_zone = "${var.aws_region}c"

  tags = {
    Name = "subnet-yiweee-private-1c"
  }
}

# === 路由表(route table)設定 ===
resource "aws_route_table" "public" { # 建立一個 Route Table，並綁定到 VPC
  vpc_id = aws_vpc.yiweee.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.yiweee.id
  }

  tags = {
    Name = "rt-yiweee-public"
  }
}

resource "aws_route_table_association" "public_1a" { # 將 Public Subnet(1a) 綁定到 Route Table
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_1c" { # 將 Public Subnet(1c) 綁定到 Route Table
  subnet_id      = aws_subnet.public_1c.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" { # 建立一個 Route Table，並綁定到 VPC
  vpc_id = aws_vpc.yiweee.id

  route {
    cidr_block = var.vpc_cidr
    gateway_id = "local"
  }

  tags = {
    Name = "rt-yiweee-private"
  }
}

resource "aws_route_table_association" "private_1a" { # 將 Private Subnet(1a) 綁定到 Route Table
  subnet_id      = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_1c" { # 將 Private Subnet(1c) 綁定到 Route Table
  subnet_id      = aws_subnet.private_1c.id
  route_table_id = aws_route_table.private.id
}

# === 安全組(Security Group)設定 === 
resource "aws_security_group" "web" { # EC2(web server) 的 Security Group
  name        = "yiweee-sg-web"
  description = "Security group for WordPress web server"
  vpc_id      = aws_vpc.yiweee.id

  tags = {
    Name = "sg-yiweee-web"
  }
}

resource "aws_security_group" "alb" { # ALB 的 Security Group
  name        = "yiweee-sg-alb"
  description = "Security group for the public ALB"
  vpc_id      = aws_vpc.yiweee.id

  tags = {
    Name = "sg-yiweee-alb"
  }
}

resource "aws_security_group_rule" "alb_http" { # ALB 的 Security Group 規則，允許 HTTP 進來（listener 會轉導 HTTPS）
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_https" { # ALB 的 Security Group 規則，允許 HTTPS 流量
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_egress" { # ALB 的 Security Group 規則，只允許送往 EC2(web server) 的 HTTP
  type                     = "egress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.web.id
  security_group_id        = aws_security_group.alb.id
}

resource "aws_security_group_rule" "web_http" { # EC2(web server) 的 Security Group 規則，只允許來自 ALB 的 HTTP 流量
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.web.id
}

resource "aws_security_group_rule" "web_ssh" { # EC2(web server) 的 Security Group 規則，允許 SSH 流量
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.admin_cidr]
  security_group_id = aws_security_group.web.id
}

resource "aws_security_group_rule" "web_egress" { # EC2(web server) 的 Security Group 規則，允許出站流量
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}

resource "aws_security_group" "db" { # RDS MySQL 的 Security Group
  name        = "yiweee-sg-db"
  description = "Security group for RDS MySQL"
  vpc_id      = aws_vpc.yiweee.id

  tags = {
    Name = "sg-yiweee-db"
  }
}

resource "aws_security_group_rule" "db_mysql" { # RDS MySQL 的 Security Group 規則，允許 EC2(web server) 連線到 RDS MySQL
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.web.id
  security_group_id        = aws_security_group.db.id
}

resource "aws_security_group_rule" "db_egress" { # RDS MySQL 的 Security Group 規則，允許出站流量
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.db.id
}

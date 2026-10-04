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

resource "aws_security_group_rule" "web_http" { # EC2(web server) 的 Security Group 規則，允許 HTTP 流量
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
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

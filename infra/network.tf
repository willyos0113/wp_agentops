# VPC 與 Subnet 資料來源
data "aws_vpc" "default" {
  id = var.default_vpc_id
}

data "aws_subnets" "subnet_ids" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group
resource "aws_security_group" "gitlab" {
  name                   = "gitlab-server"
  description            = "It used for gitlab server."
  vpc_id                 = data.aws_vpc.default.id
  tags                   = { Name = "Gitlab-Server" }
  revoke_rules_on_delete = null
}

# Security Group Rules
resource "aws_security_group_rule" "gitlab_igress_22" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  cidr_blocks       = [var.admin_cidr]
  protocol          = "tcp"
  security_group_id = aws_security_group.gitlab.id
}

resource "aws_security_group_rule" "gitlab_egress_22" {
  type              = "egress"
  from_port         = 22
  to_port           = 22
  cidr_blocks       = [var.admin_cidr]
  protocol          = "tcp"
  security_group_id = aws_security_group.gitlab.id
}

resource "aws_security_group_rule" "gitlab_igress_80" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  cidr_blocks       = [var.admin_cidr]
  protocol          = "tcp"
  security_group_id = aws_security_group.gitlab.id
}

resource "aws_security_group_rule" "gitlab_egress_80" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  cidr_blocks       = ["0.0.0.0/0"]
  protocol          = "tcp"
  security_group_id = aws_security_group.gitlab.id
}

resource "aws_security_group_rule" "gitlab_igress_443" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = [var.admin_cidr]
  protocol          = "tcp"
  security_group_id = aws_security_group.gitlab.id
}

resource "aws_security_group_rule" "gitlab_egress_443" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["0.0.0.0/0"]
  protocol          = "tcp"
  security_group_id = aws_security_group.gitlab.id
}

# ========================================
# Terraform ALB + ACM (HTTPS) Configuration
# ========================================

# === HTTPS 流量流程（TLS 在 ALB 終止，ALB 到 EC2 之間走 VPC 內的 HTTP）===
# 憑證：
# [ aws_acm_certificate ] (向 ACM 申請網域憑證，驗證方式為 DNS)
#        │
#        ▼ (ACM 給出要建立的 CNAME)
# [ cloudflare_record.acm_validation ] (網域的 DNS 在 Cloudflare，由 Terraform 自動建立驗證記錄)
#        │
#        ▼ (ACM 查到記錄後簽發憑證)
# [ aws_acm_certificate_validation ] (等憑證狀態變成 ISSUED，ALB 才能掛上去)
#
# 流量：
# [ 使用者 ] ──► (DNS 查詢 yiweee.com)
#        │
#        ▼
# [ cloudflare_record.site ] (CNAME 指向 ALB；僅 DNS，不經 Cloudflare 代理，由 ALB 出示 ACM 憑證)
#        │
#        ▼
# [ aws_lb ] (放在 public 1a / 1c 兩個 subnet，SG 見 network.tf)
#        │
#        ├─ [ listener 80 ] ──► (301 轉導 HTTPS)
#        └─ [ listener 443 ] ──► (掛 ACM 憑證) ──► [ target group ] ──► [ EC2:80 ]

# === ACM 憑證 ===
resource "aws_acm_certificate" "yiweee" { # 申請網域憑證
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true # 避免憑證被刪掉後，ALB 失去憑證而無法提供 HTTPS
  }

  tags = {
    Name = "acm-yiweee"
  }
}

# === Cloudflare DNS 記錄 ===
data "cloudflare_zone" "yiweee" { # 取得網域在 Cloudflare 的 zone
  name = var.domain_name
}

resource "cloudflare_record" "acm_validation" { # 建立 ACM 要求的 DNS 驗證記錄(DNS CNAME)
  for_each = {
    for dvo in aws_acm_certificate.yiweee.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      type    = dvo.resource_record_type
      content = dvo.resource_record_value
    }
  }

  zone_id         = data.cloudflare_zone.yiweee.id
  name            = trimsuffix(each.value.name, ".")
  type            = each.value.type
  content         = trimsuffix(each.value.content, ".")
  ttl             = 60
  proxied         = false # 驗證記錄不可經過代理
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "yiweee" { # 等 ACM 查到驗證記錄、憑證簽發完成
  certificate_arn         = aws_acm_certificate.yiweee.arn
  validation_record_fqdns = [for r in cloudflare_record.acm_validation : r.hostname]
}

resource "cloudflare_record" "site" { # 網域指向 ALB（根網域的 CNAME 由 Cloudflare 自動攤平）
  zone_id = data.cloudflare_zone.yiweee.id
  name    = var.domain_name
  type    = "CNAME"
  content = aws_lb.yiweee.dns_name
  ttl     = 60
  proxied = false # 僅 DNS：使用者直連 ALB，TLS 由 ACM 憑證終止
}

# === ALB ===
resource "aws_lb" "yiweee" { # 對外的 Application Load Balancer，橫跨兩個 AZ 的 public subnet
  name               = "alb-yiweee"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1a.id, aws_subnet.public_1c.id]
  idle_timeout       = 120 # 預設 60 秒；DB 連不上時 WordPress 約等 60 秒才回 500，調高避免 ALB 先回 504 而讓 5xx 不進 Apache access log

  tags = {
    Name = "alb-yiweee"
  }
}

resource "aws_lb_target_group" "web" { # ALB 轉送的目標：EC2 的 80 port
  name        = "tg-yiweee-web"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.yiweee.id
  target_type = "instance"

  health_check {
    path    = "/"
    matcher = "200-399" # WordPress 尚未安裝時首頁回 302，也視為健康
  }

  tags = {
    Name = "tg-yiweee-web"
  }
}

resource "aws_lb_target_group_attachment" "web" { # 把 EC2 登記到 target group
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web.id
  port             = 80
}

resource "aws_lb_listener" "http" { # 80：一律轉導 HTTPS
  load_balancer_arn = aws_lb.yiweee.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" { # 443：掛 ACM 憑證，轉送到 target group
  load_balancer_arn = aws_lb.yiweee.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.yiweee.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

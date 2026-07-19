# ═══════════════════════════════════════════════════════════════════
#  ALB (Application Load Balancer) — 인터넷 트래픽을 App 서버로 분산
# ═══════════════════════════════════════════════════════════════════

# ┌───────────────────────────────────────────────────────────┐
# │ Target Group: 트래픽을 받을 대상(app 서버) 그룹 + 헬스체크    │
# │   ASG가 만든 인스턴스가 여기에 자동 등록된다                  │
# └───────────────────────────────────────────────────────────┘
resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # 헬스체크: 각 서버의 "/" 경로에 요청해 200 응답이 오는지 확인
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    healthy_threshold   = 2  # 2번 연속 성공하면 "건강함"
    unhealthy_threshold = 2  # 2번 연속 실패하면 "비정상" → 트래픽 제외
    timeout             = 5
    interval            = 15 # 15초마다 체크
  }

  tags = { Name = "${var.project_name}-app-tg" }
}

# ┌───────────────────────────────────────────────────────────┐
# │ ALB 본체 — public 서브넷(2a/2c)에 걸쳐 배치, 인터넷 대면      │
# └───────────────────────────────────────────────────────────┘
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false           # 인터넷 대면(false) — 외부에서 접근 가능
  load_balancer_type = "application"   # ALB (L7)
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_c.id] # 2개 AZ 필수

  tags = { Name = "${var.project_name}-alb" }
}

# ┌───────────────────────────────────────────────────────────┐
# │ Listener: 80 포트로 들어온 요청을 Target Group으로 전달       │
# └───────────────────────────────────────────────────────────┘
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# apply 후 접속할 ALB 주소 출력
output "alb_dns_name" {
  description = "ALB 주소 (브라우저로 http:// 접속)"
  value       = aws_lb.main.dns_name
}

# ═══════════════════════════════════════════════════════════════════
#  App Tier — Launch Template + Auto Scaling Group
#  private(app) 서브넷에 웹/앱 서버 무리를 자동 관리로 배치
# ═══════════════════════════════════════════════════════════════════

# ┌─ AMI 조회: 최신 Amazon Linux 2023 ─┐
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# ┌───────────────────────────────────────────────────────────┐
# │ ALB용 보안 그룹: 인터넷 → ALB (HTTP 80) 허용                 │
# │   (ALB 리소스 자체는 다음 단계에서 만들고, SG는 미리 정의)     │
# └───────────────────────────────────────────────────────────┘
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP from internet to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# ┌───────────────────────────────────────────────────────────┐
# │ App용 보안 그룹: "ALB SG에서 오는" HTTP(80)만 허용            │
# │   → IP가 아니라 보안그룹을 출발지로 지정 (심층 방어)          │
# └───────────────────────────────────────────────────────────┘
resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Allow HTTP only from ALB security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # ★ 출발지 = ALB의 SG
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # 아웃바운드는 NAT 통해 나감
  }

  tags = { Name = "${var.project_name}-app-sg" }
}

# ┌───────────────────────────────────────────────────────────┐
# │ Launch Template — 서버를 "어떻게 찍어낼지"의 설계도           │
# └───────────────────────────────────────────────────────────┘
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-app-"
  image_id      = data.aws_ami.al2023.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.app.id]

  # 부팅 시 웹서버 설치 + 어느 서버인지 표시 (로드밸런싱 확인용)
  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf install -y httpd
    systemctl enable --now httpd
    echo "<h1>App Tier 응답 성공!</h1>" > /var/www/html/index.html
    echo "<p>이 응답을 처리한 서버: $(hostname)</p>" >> /var/www/html/index.html
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project_name}-app" }
  }
}

# ┌───────────────────────────────────────────────────────────┐
# │ Auto Scaling Group — 설계도로 서버 무리를 유지/관리          │
# └───────────────────────────────────────────────────────────┘
resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-app-asg"
  min_size            = 2 # 항상 최소 2대
  max_size            = 4 # 최대 4대까지 증설 가능
  desired_capacity    = 2 # 지금은 2대 유지
  vpc_zone_identifier = [aws_subnet.app_a.id, aws_subnet.app_c.id] # 2a/2c 분산

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # ASG가 만든 인스턴스를 ALB의 Target Group에 자동 등록
  target_group_arns = [aws_lb_target_group.app.arn]

  health_check_type = "ELB" # ALB 헬스체크 기준으로 건강 판단 (응답 못하면 교체)

  tag {
    key                 = "Name"
    value               = "${var.project_name}-app"
    propagate_at_launch = true
  }
}

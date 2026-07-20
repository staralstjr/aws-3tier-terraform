# ═══════════════════════════════════════════════════════════════════
#  DB Tier — RDS (관리형 관계형 데이터베이스)
#  private(db) 서브넷에 배치, App tier에서만 접근 가능
# ═══════════════════════════════════════════════════════════════════

# DB 마스터 비밀번호 (값은 깃에 안 올라가는 terraform.tfvars에서 주입)
variable "db_password" {
  description = "RDS 마스터 사용자 비밀번호"
  type        = string
  sensitive   = true # ★ 터미널 출력/로그에 값이 노출되지 않게 가림
}

# ┌───────────────────────────────────────────────────────────┐
# │ DB 서브넷 그룹: RDS가 살 수 있는 서브넷 목록                   │
# │   최소 2개 AZ 필수 (장애 시 다른 AZ로 전환 가능해야 하므로)    │
# └───────────────────────────────────────────────────────────┘
resource "aws_db_subnet_group" "main" {
  # 서브넷 그룹 이름도 '문자'로 시작해야 함 (RDS 계열 공통 규칙)
  name       = "db-subnet-group-${var.project_name}"
  subnet_ids = [aws_subnet.db_a.id, aws_subnet.db_c.id]

  tags = { Name = "${var.project_name}-db-subnet-group" }
}

# ┌───────────────────────────────────────────────────────────┐
# │ DB 보안그룹: App 보안그룹에서 오는 MySQL(3306)만 허용          │
# │   → 인터넷은 물론 ALB에서도 직접 접근 불가                    │
# └───────────────────────────────────────────────────────────┘
resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Allow MySQL only from App tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from App tier only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id] # ★ 출발지 = App의 SG
  }

  # egress 규칙 없음 = 아웃바운드 전면 차단.
  # DB는 스스로 인터넷에 나갈 일이 없으므로 최소 권한 원칙 적용.

  tags = { Name = "${var.project_name}-db-sg" }
}

# ┌───────────────────────────────────────────────────────────┐
# │ RDS 인스턴스 (MySQL)                                        │
# └───────────────────────────────────────────────────────────┘
resource "aws_db_instance" "main" {
  # RDS 식별자는 반드시 '문자'로 시작해야 함 (project_name이 "3tier"라 숫자로 시작하므로 접두사 사용)
  identifier     = "db-${var.project_name}"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  allocated_storage = 20 # GB (gp3 최소)
  storage_type      = "gp3"
  storage_encrypted = true # 저장 데이터 암호화

  db_name  = "appdb"
  username = "dbadmin"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  publicly_accessible = false # ★ 인터넷에서 접근 불가 (private 전용)
  multi_az            = false # 학습용 비용 절감. 운영 환경은 true(대기 서버 자동 전환)

  skip_final_snapshot = true # 학습용: destroy 시 최종 스냅샷 없이 바로 삭제

  tags = { Name = "${var.project_name}-db" }
}

# DB 접속 주소 출력 (앱이 사용할 엔드포인트)
output "rds_endpoint" {
  description = "RDS 접속 엔드포인트 (App tier에서만 접근 가능)"
  value       = aws_db_instance.main.endpoint
}

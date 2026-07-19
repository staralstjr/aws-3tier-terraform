# ═══════════════════════════════════════════════════════════════════
#  서브넷: VPC(10.0.0.0/16) 안을 tier 3개 × AZ 2개 = 6개로 나눈다
#
#  주소 규칙:  10.0.[tier][az].0/24
#    tier →  0번대=Public, 10번대=App, 20번대=DB
#    az   →  ...0=2a, ...1=2c
# ═══════════════════════════════════════════════════════════════════

# ┌───────────────────────────────────────────────────────────┐
# │ Tier 1: Public 서브넷 (인터넷과 연결되는 "1층 로비")          │
# │   map_public_ip_on_launch = true → 여기 만든 서버는           │
# │   공인 IP를 자동으로 받음 (인터넷에서 접근 가능해야 하므로)     │
# └───────────────────────────────────────────────────────────┘
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id        # 우리가 만든 VPC 안에 소속
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-2a"
    Tier = "public"
  }
}

resource "aws_subnet" "public_c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-2c"
    Tier = "public"
  }
}

# ┌───────────────────────────────────────────────────────────┐
# │ Tier 2: Private App 서브넷 ("직원 사무실")                    │
# │   공인 IP 자동할당 없음 → 외부에서 직접 접근 불가             │
# └───────────────────────────────────────────────────────────┘
resource "aws_subnet" "app_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "ap-northeast-2a"

  tags = {
    Name = "${var.project_name}-app-2a"
    Tier = "app"
  }
}

resource "aws_subnet" "app_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "ap-northeast-2c"

  tags = {
    Name = "${var.project_name}-app-2c"
    Tier = "app"
  }
}

# ┌───────────────────────────────────────────────────────────┐
# │ Tier 3: Private DB 서브넷 ("지하 금고")                       │
# └───────────────────────────────────────────────────────────┘
resource "aws_subnet" "db_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.20.0/24"
  availability_zone = "ap-northeast-2a"

  tags = {
    Name = "${var.project_name}-db-2a"
    Tier = "db"
  }
}

resource "aws_subnet" "db_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.21.0/24"
  availability_zone = "ap-northeast-2c"

  tags = {
    Name = "${var.project_name}-db-2c"
    Tier = "db"
  }
}

# ═══════════════════════════════════════════════════════════════════
#  인터넷 연결: Internet Gateway + Public 라우팅
#  → public 서브넷을 실제로 인터넷과 연결한다
# ═══════════════════════════════════════════════════════════════════

# ┌───────────────────────────────────────────────────────────┐
# │ Internet Gateway (IGW) — VPC를 인터넷에 연결하는 "정문"       │
# └───────────────────────────────────────────────────────────┘
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ┌───────────────────────────────────────────────────────────┐
# │ Public 라우팅 테이블 — "인터넷으로 가려면 IGW로" 길 안내판    │
# │   (10.0.0.0/16 → local 규칙은 자동으로 포함됨)              │
# └───────────────────────────────────────────────────────────┘
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"                     # 모든 목적지(=인터넷 전체)
    gateway_id = aws_internet_gateway.igw.id     # → IGW(정문)로 내보내라
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# ┌───────────────────────────────────────────────────────────┐
# │ 라우팅 테이블을 public 서브넷에 "연결"                        │
# │   연결해야 그 서브넷이 이 안내판을 따른다                     │
# └───────────────────────────────────────────────────────────┘
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

# ═══════════════════════════════════════════════════════════════════
#  NAT Gateway — private(App) 서브넷의 "나가기 전용" 인터넷 출구
#  ⚠️ 유료 리소스 (시간당 ~$0.045 + 데이터). 실습 후 destroy 권장.
# ═══════════════════════════════════════════════════════════════════

# ┌───────────────────────────────────────────────────────────┐
# │ Elastic IP: NAT Gateway가 사용할 고정 공인 IP                │
# │   (browser.py의 맥미니 사무실 IP 역할)                       │
# └───────────────────────────────────────────────────────────┘
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

# ┌───────────────────────────────────────────────────────────┐
# │ NAT Gateway: public 서브넷에 배치 (여기서 IGW로 이어짐)      │
# └───────────────────────────────────────────────────────────┘
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id          # 위 Elastic IP 사용
  subnet_id     = aws_subnet.public_a.id  # ★ public 서브넷에 있어야 동작

  tags = {
    Name = "${var.project_name}-nat"
  }

  # IGW가 먼저 있어야 NAT가 인터넷으로 나갈 수 있음
  depends_on = [aws_internet_gateway.igw]
}

# NAT Gateway 는 원래 운영 환경에서는 AZ마다 하나씩(2개) 두는게 정석이죠. 고가용성을 위해서 AWS SAA C03에서 배웠던 기억이 납니다. 
# 근데 이게 실습할 때 유료라서 9학습용으로 1개만 뒀습니다! 


# ┌───────────────────────────────────────────────────────────┐
# │ App 서브넷용 private 라우팅 테이블: 0.0.0.0/0 → NAT Gateway  │
# └───────────────────────────────────────────────────────────┘
resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"                  # 인터넷으로 가는 트래픽은
    nat_gateway_id = aws_nat_gateway.main.id      # → NAT Gateway로 (IGW 아님!)
  }

  tags = {
    Name = "${var.project_name}-private-app-rt"
  }
}

# App 서브넷(2a, 2c)만 이 라우팅 테이블에 연결
# → DB 서브넷은 연결 안 함: 인터넷 나갈 일 없으니 완전 격리 유지 (더 안전)
resource "aws_route_table_association" "app_a" {
  subnet_id      = aws_subnet.app_a.id
  route_table_id = aws_route_table.private_app.id
}

resource "aws_route_table_association" "app_c" {
  subnet_id      = aws_subnet.app_c.id
  route_table_id = aws_route_table.private_app.id
}

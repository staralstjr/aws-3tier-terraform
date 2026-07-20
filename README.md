# AWS 3-Tier 망분리 아키텍처 (Terraform)

외부 공격 방어 · 고가용성 · 확장성을 갖춘 **3-Tier 웹 서비스 인프라**를
**코드(Terraform / IaC)** 로 구축하는 학습 프로젝트.

> 클라우드 개발자로의 커리어 전환 과정에서, AWS SAA로 다진 개념을 실제 인프라 코드로 옮기며 진행 중.

## 🏛️ 아키텍처

```
                          [ Internet ]
                               │
                        Internet Gateway
                               │
        ┌──────────────── VPC 10.0.0.0/16 ────────────────┐
        │                                                  │
        │   AZ ap-northeast-2a          AZ ap-northeast-2c │
        │  ┌────────────────┐         ┌────────────────┐   │
Public  │  │ 10.0.0.0/24    │         │ 10.0.1.0/24    │   │  ← ALB, NAT GW
        │  └────────────────┘         └────────────────┘   │
        │  ┌────────────────┐         ┌────────────────┐   │
App     │  │ 10.0.10.0/24   │         │ 10.0.11.0/24   │   │  ← EC2 + Auto Scaling
(private)│  └────────────────┘         └────────────────┘   │
        │  ┌────────────────┐         ┌────────────────┐   │
DB      │  │ 10.0.20.0/24   │         │ 10.0.21.0/24   │   │  ← RDS
(private)│  └────────────────┘         └────────────────┘   │
        └──────────────────────────────────────────────────┘
```

- **다중 AZ**: 서울 리전의 두 가용 영역(2a/2c)에 인프라를 분산해 고가용성 확보
- **망분리**: DB·App은 private 서브넷에 배치, 외부에서 직접 접근 불가
- **주소 규칙**: `10.0.[tier][az].0/24` (3옥텟 0번대=public, 10번대=app, 20번대=db)

## 🛠️ 기술 스택

- **IaC**: Terraform 1.15
- **Cloud**: AWS (VPC, EC2, ALB, Auto Scaling, RDS, NAT Gateway)
- **Region**: ap-northeast-2 (Seoul)

## 📁 구조

```
├── main.tf         # provider(AWS) + VPC
├── variables.tf    # 프로젝트 공통 변수
├── subnets.tf      # 서브넷 6개 (tier 3 × AZ 2)
└── docs/           # 진행 기록 및 학습 정리
```

## 🚀 사용법

```bash
terraform init      # provider 다운로드
terraform plan      # 변경사항 미리보기
terraform apply     # 실제 생성
terraform destroy   # 전체 정리
```

## ✅ 진행 상황

- [x] VPC + 다중 AZ 서브넷 (network foundation)
- [x] Internet Gateway + 라우팅
- [x] NAT Gateway (private 서브넷 인터넷 출구)
- [x] EC2 + Auto Scaling Group (App tier)
- [x] Application Load Balancer
- [x] RDS + Security Group (DB tier)

**3-tier 아키텍처 구축 완료.** 실제 배포 후 아래를 검증했다.

- **로드밸런싱 · 멀티 AZ** — ALB 접속 시 2a/2c 서버가 교대로 응답
- **자가 치유** — App 서버 강제 종료 → 무중단 유지 → ASG가 동일 AZ에 자동 재생성
- **DB 격리** — 외부에서 RDS 접속 시도 시 타임아웃(사설 IP, App tier만 접근 가능)

### 다음 계획

- [ ] Auto Scaling 정책 (CPU 기반 스케일 인/아웃)
- [ ] CI/CD — GitHub Actions로 `terraform plan` 자동화
- [ ] 애플리케이션 컨테이너화 (Docker)

## 📚 문서

| 문서 | 내용 |
|------|------|
| [progress-01-network-foundation.md](docs/progress-01-network-foundation.md) | 네트워크 기반 구축 기록 + 필요 선행지식 분석 |
| [concept-routing-igw.md](docs/concept-routing-igw.md) | 라우팅 테이블 · Internet Gateway · 서브넷 연결 |
| [concept-nat-gateway.md](docs/concept-nat-gateway.md) | NAT Gateway · private 서브넷 아웃바운드 |
| [concept-app-tier-alb.md](docs/concept-app-tier-alb.md) | Launch Template · ASG · ALB · 자가 치유 실증 |
| [concept-db-tier-rds.md](docs/concept-db-tier-rds.md) | RDS · 보안 사슬 · 격리 검증 |

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
- [ ] Internet Gateway + 라우팅
- [ ] NAT Gateway (private 서브넷 인터넷 출구)
- [ ] EC2 + Auto Scaling Group (App tier)
- [ ] Application Load Balancer
- [ ] RDS + Security Group (DB tier)

자세한 진행 기록은 [`docs/`](docs/) 참고.

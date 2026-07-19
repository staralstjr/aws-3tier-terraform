# 진행 기록 #01 — 네트워크 기반 구축 (VPC + 서브넷)

> AWS 3-Tier 망분리 아키텍처 프로젝트의 1단계 작업 기록.
> 무엇을 했는지 + **각 작업에 어떤 기초 지식이 필요했는지**를 함께 정리한다.

작업일: 2026-07-18 ~ 07-19 · 리전: `ap-northeast-2`(서울) · 도구: Terraform 1.15.8, AWS CLI 2.36

---

## 1. 지금까지 완성된 아키텍처

```
VPC  3tier-vpc  (10.0.0.0/16)
│
├─ [AZ ap-northeast-2a]
│    ├─ 3tier-public-2a   10.0.0.0/24    (공인 IP 자동)
│    ├─ 3tier-app-2a      10.0.10.0/24   (private)
│    └─ 3tier-db-2a       10.0.20.0/24   (private)
│
└─ [AZ ap-northeast-2c]
     ├─ 3tier-public-2c   10.0.1.0/24    (공인 IP 자동)
     ├─ 3tier-app-2c      10.0.11.0/24   (private)
     └─ 3tier-db-2c       10.0.21.0/24   (private)
```

- **VPC 1개** + **서브넷 6개**(tier 3종 × AZ 2곳). 전부 무료 리소스.
- 주소 규칙: `10.0.[tier][az].0/24` — 3옥텟 `0번대`=public, `10번대`=app, `20번대`=db.
- 파일 구성: `main.tf`(provider+VPC), `variables.tf`(project_name), `subnets.tf`(서브넷 6개).

---

## 2. 작업 타임라인 (한 것 + 필요했던 개념)

### 단계 0 — 도구 설치 & 자격증명 등록
- **한 것:** Homebrew로 AWS CLI·Terraform 설치, IAM 사용자(`terraform-admin`) 생성, `aws configure`로 Access Key 등록.
- **필요했던 개념:** IAM 사용자 vs 루트 계정, Access Key(프로그래밍 자격증명)의 개념, 최소권한/보안 원칙.

### 단계 1 — 비용 추적 & 정리 (계정 청소)
- **한 것:** 청구서를 서비스별로 분석 → 방치된 EC2(`instagram-server`)가 매달 ~$15 소모 중임을 추적 → terminate로 정리.
- **필요했던 개념:** 클라우드 종량제 과금 모델, "VPC 항목 비용 = 공인 IPv4/NAT Gateway" 같은 청구서 해독, EC2 **중지(stop) vs 종료(terminate)** 차이, EBS 볼륨 개념.

### 단계 2 — VPC 생성 (첫 Terraform)
- **한 것:** `10.0.0.0/16` VPC를 Terraform 코드로 작성 → `init` → `plan` → `apply`.
- **필요했던 개념:** IP 주소(32비트)·CIDR 표기(`/16`)·주소 개수 계산, 사설 IP 대역(RFC1918), IaC/선언형의 의미, Terraform의 provider·resource·state, plan→apply 워크플로.

### 단계 3 — 서브넷 6개 생성 (다중 AZ)
- **한 것:** VPC를 tier 3 × AZ 2 = 6개 서브넷으로 분할. public에만 공인 IP 자동할당. 이름은 변수로 관리.
- **필요했던 개념:** **서브네팅**(CIDR로 큰 네트워크를 쪼개기), 공인 vs 사설 서브넷, **Region/AZ와 고가용성(HA)**, Terraform 리소스 **참조**(`aws_vpc.main.id`)와 의존성 자동해결, 변수·문자열 보간(`${var...}`), DRY 원칙.

---

## 3. 이 작업, 얼마나 어려운 작업이었나? (기초 지식 분석)

핵심 결론부터: **"코드를 쳐서 동작시키는 것"은 쉽지만, "왜 이렇게 하는지 알고 하는 것"은 네트워크 기초 위에서만 가능하다.**

Terraform 코드 자체는 몇 줄 안 되고 선언형이라 진입장벽이 낮다. 하지만 *제대로* 하려면
아래 지식이 밑에 깔려 있어야 한다. 무엇이 **선행 지식**이고 무엇이 **하면서 배워도 되는지** 구분하면:

| 개념 | 분류 | 난이도 | 비고 |
|------|------|--------|------|
| IP 주소 / CIDR / 서브네팅 | **선행 필수** | ★★☆ | 이게 없으면 주소 설계 자체가 불가능. 이 프로젝트의 진짜 토대 |
| 공인 IP vs 사설 IP | **선행 필수** | ★☆☆ | public/private 서브넷 구분의 근거 |
| Region / AZ / 고가용성 | 선행 권장 | ★☆☆ | 개념은 단순, 안 두면 왜 2벌 만드는지 이해 안 됨 |
| IAM 사용자 / Access Key / 보안 | 선행 권장 | ★★☆ | 초기 세팅에 필요. 잘못하면 보안 사고 |
| 클라우드 과금 모델 | 실무 감각 | ★★☆ | 몰라도 진행은 되나, 모르면 돈이 샌다 |
| IaC / 선언형 / provider·resource·state | **하면서 배움** | ★★☆ | Terraform 특유 개념. 실습으로 체득 |
| 리소스 참조 · 변수 · 보간 | **하면서 배움** | ★☆☆ | Terraform 문법. 반복하면 익숙해짐 |

### 총평
- **손(mechanical) 난이도: 낮음.** 리소스 블록 몇 개 + `apply`가 전부.
- **머리(conceptual) 난이도: 네트워크 기초에 달림.** 특히 **IP/CIDR/서브네팅**과 **public·private 구분**이
  없으면, 코드는 복붙해도 "왜 이 주소를, 왜 이렇게 나누는지"를 설명하지 못한다. 포트폴리오·면접에서
  갈리는 지점이 바로 여기다.
- **AWS SAA 자격증 범위**가 위 개념 대부분(VPC/서브넷/AZ/IAM/과금)을 커버한다. 즉 SAA를 땄다면
  *개념적 선행 지식은 이미 갖춘 상태*이고, 남은 건 그것을 **코드(Terraform)로 손에 익히는 일**이다.

> 한 줄 요약: **네트워크 기초(IP·CIDR·서브넷·public/private)는 선행 필수, Terraform 문법은 하면서 배우면 된다.**

---

## 4. 아직 안 한 것 (다음 단계)

현재 서브넷은 만들었지만 **인터넷과 연결되는 "문과 길"이 없다.** public 서브넷도 아직 실제로는 인터넷에 못 나간다.

- [ ] **Internet Gateway (IGW)** — VPC를 인터넷에 연결하는 정문
- [ ] **라우팅 테이블** — "인터넷으로 가려면 IGW로" 길 안내 → public 서브넷에 연결
- [ ] **NAT Gateway** — private(App) 서브넷의 인터넷 출구 (browser.py의 맥미니 프록시 역할)
- [ ] **EC2 + Auto Scaling Group** — App tier 서버
- [ ] **ALB** — 트래픽 분산 (public에 배치)
- [ ] **RDS + Security Group** — DB tier

---

*관련 문서: [network-bypass-proxy-tunnel.md](network-bypass-proxy-tunnel.md) — 이 프로젝트의 계기가 된
온프레미스 IP 우회 사례. NAT Gateway 개념과 직접 연결됨.*

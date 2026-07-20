# 개념 정리 — App Tier (Launch Template · Auto Scaling · ALB)

> `app.tf` + `alb.tf` 코드가 무엇을 구성하는지, 그리고 실제로 확인한 동작 정리.
> 인터넷 트래픽이 private App 서버까지 도달하고 분산되는 전체 경로.

관련 코드: [`app.tf`](../app.tf), [`alb.tf`](../alb.tf) · 선행: [concept-nat-gateway.md](concept-nat-gateway.md)

---

## 1. 왜 단일 EC2가 아니라 ASG인가

서버를 `aws_instance` 1대로 두면: 그 서버가 죽으면 서비스 중단, 트래픽 급증 시 감당 불가.
그래서 **서버를 개별 관리하지 않고, 자동 관리되는 무리(fleet)** 로 운영한다.

- **Launch Template**: 서버를 "어떻게 찍어낼지"의 설계도(불변 스펙).
- **Auto Scaling Group(ASG)**: 그 설계도로 서버 무리를 유지·복구·확장.

---

## 2. Launch Template — 서버 설계도

어떤 AMI로, 어떤 인스턴스 타입으로, 어떤 보안그룹을 달고, 부팅 시 무엇을 실행할지 정의한다.
실제 서버를 만드는 게 아니라 "찍어낼 틀"만 정의한다.

- `image_id` = 최신 Amazon Linux 2023 (data source로 조회)
- `instance_type` = t3.micro
- `vpc_security_group_ids` = App 보안그룹
- `user_data` = 부팅 시 httpd 설치 + 응답 페이지 생성 (base64 인코딩 필요)

---

## 3. Auto Scaling Group — 무리 관리자

핵심은 세 숫자: **min / desired / max** (이 프로젝트: 2 / 2 / 4).

- 항상 **최소 2대 유지** — 1대 죽으면 자동으로 새로 띄움(**자가 치유**)
- desired 2대를 **2a / 2c 서브넷에 분산** (`vpc_zone_identifier`) → 멀티 AZ 고가용성
- 트래픽 증가 시 **최대 4대까지 자동 증설** (스케일링 정책 추가 시)
- `health_check_type = "ELB"` → ALB 헬스체크 기준으로 건강 판단, 응답 못 하면 교체

---

## 4. 로드밸런서: ELB vs ALB

- **ELB(Elastic Load Balancing)** = AWS 로드밸런서 서비스 **패밀리 전체 이름**.
- 그 안에 종류가 여러 개: **ALB**(L7, HTTP), **NLB**(L4, TCP/UDP), GWLB(L3), CLB(레거시).

| 종류 | 계층 | 특징 | 용도 |
|------|------|------|------|
| **ALB** | L7 (HTTP) | URL·헤더 기반 라우팅, HTTP 헬스체크 | **웹 앱** (이 프로젝트) |
| NLB | L4 (TCP/UDP) | 초고속, 고정 IP | 극한 성능, 비-HTTP |
| GWLB | L3 | 어플라이언스(방화벽 등) | 보안 장비 |
| CLB | L4/기본 L7 | 구형 | 신규 사용 지양 |

**우리가 ALB를 쓰는 이유:** 웹서비스(HTTP)이므로 L7에서 내용을 이해하는 ALB가 적합.
경로 기반 라우팅, HTTP 헬스체크, Target Group·ASG 연동이 매끄럽다.

---

## 5. ALB의 3부품

ALB는 인스턴스를 직접 알지 못하고, 아래 3개로 나눠 동작한다.

| 부품 | 역할 |
|------|------|
| **Target Group** | 트래픽을 받을 대상(app 서버) 명단 + 헬스체크. ASG가 만든 인스턴스가 자동 등록됨 |
| **ALB 본체** | public 서브넷(2a/2c)에 걸쳐 인터넷을 대면 (2개 이상 AZ 필수) |
| **Listener** | "80 포트로 들어온 요청 → Target Group으로 전달" 규칙 |

- **헬스체크**: 각 대상의 `/` 경로에 주기적으로 요청해 `200`이 오는지 확인.
  실패하는 서버는 트래픽에서 자동 제외 → 사용자는 장애 서버로 안 감.

---

## 6. 계층별 보안 그룹 — 심층 방어(Defense in Depth)

| 보안그룹 | 인바운드 허용 |
|----------|---------------|
| **ALB SG** | 인터넷(`0.0.0.0/0`)에서 오는 HTTP(80) |
| **App SG** | **ALB SG에서 오는** HTTP(80)만 (IP가 아닌 보안그룹으로 출발지 지정) |

App 서버는 IP가 아니라 **"ALB SG를 통과한 트래픽"** 만 받는다. ALB IP가 바뀌어도 규칙은 유효.
→ App 서버로의 직접 접근은 원천 차단, 오직 ALB 경유만 허용.

---

## 7. 전체 요청 흐름

```
사용자 브라우저
   │  http://<ALB DNS>
   ▼
ALB (public 서브넷, ALB SG)         ← 인터넷 대면, L7
   │  Listener(80) → Target Group → 건강한 대상 선택
   ▼
App 서버 (private 서브넷, App SG, 공인 IP 없음)
   │  응답 생성 (httpd)
   ▼
ALB → 사용자에게 응답 전달

* App 서버의 아웃바운드(패키지 설치 등)는 NAT Gateway 경유로 인터넷에 나감
```

---

## 8. 실제 확인한 동작 (테스트 결과)

ALB DNS로 접속 후 새로고침을 반복하니 응답 서버가 번갈아 바뀜:

```
ip-10-0-11-86.ap-northeast-2.compute.internal   ← app-2c (AZ 2c)
ip-10-0-10-6.ap-northeast-2.compute.internal    ← app-2a (AZ 2a)
```

이 하나의 결과가 다음을 동시에 증명한다:
- **ALB 로드밸런싱** — 요청이 두 서버로 분산됨
- **멀티 AZ 고가용성** — 두 AZ의 서버가 함께 서비스 중
- **망분리** — 서버는 공인 IP 없는 private, ALB 경유로만 접근됨
- **NAT Gateway** — private 서버가 httpd를 설치할 수 있었던 것 = NAT 아웃바운드 동작 증거

---

## 8-1. 자가 치유(Self-Healing) 실증

App 서버 1대(AZ 2a)를 의도적으로 강제 종료하고 관찰했다.

| 시점 | 상태 |
|------|------|
| 종료 직후 | 2c 서버만 응답. **브라우저는 에러 없이 정상 동작** (무중단) |
| ~30초 | ALB 헬스체크가 실패 감지 → 트래픽에서 제외, 기존 인스턴스는 `draining` |
| ~2분 | ASG가 용량 부족(desired 2 > 실제 1)을 감지해 **새 인스턴스 자동 생성** |
| ~3분 | 새 인스턴스가 헬스체크 통과 → Target Group 합류 → 다시 2대가 교대 응답 |

```
종료된 인스턴스: i-05680a0ce2e62449e (2a, 10.0.10.148)
새로 생성된 것 : i-0d5dab295c61b808d (2a, 10.0.10.64)   ← ID·IP 모두 다른 새 서버
```

**관찰 포인트**
- ASG는 죽은 서버를 되살리는 게 아니라 **Launch Template으로 새로 찍어낸다**.
- 죽은 AZ(2a)와 **같은 AZ에 다시 배치** → 멀티 AZ 균형을 스스로 유지.
- `draining` = 처리 중이던 요청을 마친 뒤 제외되므로 사용자 요청이 끊기지 않음.
- **헬스체크 감지 시간** = `interval(15s) × unhealthy_threshold(2) ≈ 30초`.
  짧게 하면 빠른 감지·불안정, 길게 하면 안정·느린 감지 → 튜닝 트레이드오프.

→ 사람이 아무 조치도 하지 않았는데 **장애 감지 → 무중단 유지 → 자동 복구**가 완료됨.

---

## 9. 코드 ↔ 동작 매핑

| Terraform 리소스 | 하는 일 |
|------------------|---------|
| `aws_launch_template.app` | 서버 스펙(AMI/타입/SG/user_data) 정의 |
| `aws_autoscaling_group.app` | 서버 무리 유지(min2/desired2/max4), 멀티 AZ 분산, 자가 치유 |
| `aws_lb_target_group.app` | 대상 명단 + 헬스체크 |
| `aws_lb.main` | ALB 본체 (public 서브넷, L7) |
| `aws_lb_listener.http` | 80 요청 → Target Group 전달 |
| `aws_security_group.alb` / `.app` | 계층별 방화벽 (인터넷→ALB, ALB→App) |

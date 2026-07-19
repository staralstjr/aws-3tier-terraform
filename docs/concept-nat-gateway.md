# 개념 정리 — NAT Gateway (private 서브넷의 인터넷 출구)

> `nat.tf` 코드가 실제로 무슨 일을 하는지, 패킷 흐름과 보안 관점에서 정리.
> private 서브넷의 리소스가 "나가는 것만" 가능하게 만드는 방법.

관련 코드: [`nat.tf`](../nat.tf) · 선행 개념: [concept-routing-igw.md](concept-routing-igw.md)

---

## 1. private 서브넷의 딜레마

3-tier에서 App/DB 서버는 private 서브넷에 둔다. 이들은 라우팅 테이블에 인터넷 경로가 없어
외부에서 직접 접근할 수 없다(보안). 그런데 문제가 있다:

- App 서버도 **가끔 밖으로 나가야 한다** — OS 업데이트, 패키지 설치(`dnf install ...`), 외부 API 호출 등.
- 하지만 **밖에서 App 서버로 들어오는 연결은 여전히 차단**하고 싶다.

즉 **"나가기(outbound)는 허용, 들어오기(inbound)는 차단"** 이라는 비대칭 통로가 필요하다.
이것을 제공하는 것이 **NAT Gateway**다.

---

## 2. NAT Gateway란

- **NAT** = Network Address Translation(네트워크 주소 변환).
- private 서브넷의 리소스가 인터넷으로 나갈 때, 출발지 사설 IP를
  **NAT Gateway의 공인 IP(Elastic IP)로 변환**해서 내보낸다.
- 외부에서 보면 트래픽이 NAT Gateway의 IP에서 온 것으로 보이므로,
  private 서버의 실제 주소는 노출되지 않고 **외부에서 먼저 연결을 걸 수도 없다**.
- NAT Gateway는 반드시 **public 서브넷에 위치**해야 한다 (거기서 IGW를 통해 인터넷으로 이어지므로).

---

## 3. 작동 원리 (패킷 흐름)

```
App 서버 (10.0.10.5, 공인 IP 없음)
   │  목적지 0.0.0.0/0 (인터넷)
   ▼
private-app 라우팅 테이블:  0.0.0.0/0 → NAT Gateway
   ▼
NAT Gateway (public 서브넷, Elastic IP 보유)
   │  출발지 IP: 10.0.10.5 → NAT의 Elastic IP 로 변환
   ▼
Internet Gateway → 인터넷
   ▼
응답은 역순으로 돌아와 App 서버(10.0.10.5)에 전달됨

→ 나가기(outbound): 가능 ✅
→ 들어오기(inbound, 외부가 먼저 시작): 불가능 ❌ (공인 IP가 없으므로 지목 불가)
```

---

## 4. Elastic IP (EIP)

- NAT Gateway가 사용하는 **고정 공인 IPv4 주소**.
- 고정이므로, 외부 서비스의 방화벽에 "이 IP만 허용" 같은 화이트리스트 등록이 가능하다.
- NAT Gateway에 연결되어 사용 중이면 추가 요금이 없지만, **할당만 하고 안 쓰면 과금**된다.

---

## 5. 라우팅 타깃의 차이: IGW vs NAT Gateway

| 라우팅 테이블 | 규칙 | 타깃 종류 | 대상 서브넷 |
|----------------|------|-----------|-------------|
| public 라우팅 | `0.0.0.0/0 → IGW` | `gateway_id` | public 서브넷 |
| private-app 라우팅 | `0.0.0.0/0 → NAT` | `nat_gateway_id` | app 서브넷 |

- public 서브넷: 인터넷과 **직접** 연결 (IGW). 리소스가 공인 IP를 가짐.
- app 서브넷: NAT Gateway를 **경유**해 나감. 리소스는 공인 IP가 없음.

---

## 6. NAT Gateway vs Internet Gateway (자주 헷갈림)

| | Internet Gateway (IGW) | NAT Gateway |
|--|------------------------|-------------|
| 위치 | VPC에 연결 | public 서브넷 안에 배치 |
| 방향 | 인바운드 + 아웃바운드 | **아웃바운드 전용** |
| 대상 | 공인 IP를 가진 리소스 | 공인 IP가 **없는** private 리소스 |
| 변환 | 공인 IP ↔ 사설 IP (1:1) | 여러 사설 IP → NAT의 EIP 1개 (N:1) |
| 요금 | 무료 | **유료** (시간당 + 데이터) |

> 핵심: **IGW는 public 서브넷을 인터넷에 노출**시키고, **NAT는 private 서브넷을 노출 없이 내보낸다**.

---

## 7. DB 서브넷은 NAT에도 연결하지 않음 (완전 격리)

`nat.tf`에서는 **app 서브넷만** private-app 라우팅 테이블에 연결한다.
**DB 서브넷은 어떤 인터넷 경로에도 연결하지 않는다.**

- 데이터베이스는 인터넷으로 나갈 일이 거의 없다.
- 인터넷 경로를 아예 주지 않으면 공격 표면이 최소화된다 → **가장 안전한 계층**.
- 3-tier에서 "지하 금고"에 해당하는 DB tier의 격리 원칙.

---

## 8. 고가용성(HA) 트레이드오프

NAT Gateway는 **하나의 AZ에만** 존재한다. 그 AZ가 장애나면, 다른 AZ의 서브넷은 인터넷 출구를 잃는다.

- **운영 환경 정석:** AZ마다 NAT Gateway를 하나씩 (총 2개) 두고, 각 AZ의 private 서브넷은
  같은 AZ의 NAT를 사용하도록 라우팅한다. → 한 AZ가 죽어도 다른 AZ는 계속 나갈 수 있음.
- **이 프로젝트(학습용):** NAT Gateway가 유료(각 월 ~$32)이므로 **1개만** 두어 비용을 절감.
  대신 "왜 1개만 뒀는지"를 아는 것이 중요 (트레이드오프 인식 = 실무 감각).

*(이 내용은 AWS SAA-C03의 고가용성 설계 파트에서 다루는 개념과 동일하다.)*

---

## 9. browser.py(온프레미스)와의 대응

이 프로젝트의 계기가 된 `browser.py`의 맥미니 프록시 구조가 NAT Gateway와 정확히 대응된다.

| browser.py (직접 구현) | AWS NAT Gateway |
|------------------------|-----------------|
| 맥미니 (나가기 전용 출구) | NAT Gateway |
| 맥미니의 고정 사무실 IP | NAT Gateway의 Elastic IP |
| SSH 터널 경로 지정 | private 라우팅 테이블 (`0.0.0.0/0 → NAT`) |
| 데이터센터 서버(직접 나가면 차단) | private 서브넷의 App 서버 |

> "private 위치의 서버가, 노출 없이, 고정된 공인 IP로 바깥에 나간다"는 문제를
> 온프레미스에서는 맥미니로, 클라우드에서는 NAT Gateway로 해결한 것.

---

## 10. 비용 주의

- NAT Gateway는 **존재하기만 해도 시간당 과금**(~$0.045/hr, 월 ~$32) + 데이터 처리 요금.
- 학습 시에는 **필요할 때 apply → 테스트 → `terraform destroy`** 로 켜둔 시간을 최소화한다.

---

## 11. 코드 ↔ 동작 매핑

| Terraform 리소스 | 하는 일 |
|------------------|---------|
| `aws_eip.nat` | NAT Gateway용 고정 공인 IP(Elastic IP) 할당 |
| `aws_nat_gateway.main` | public 서브넷에 NAT Gateway 생성 (아웃바운드 변환) |
| `aws_route_table.private_app` | `0.0.0.0/0 → NAT` 규칙을 가진 private 라우팅 테이블 |
| `aws_route_table_association.app_a/c` | app 서브넷을 위 테이블에 연결 (DB는 제외) |

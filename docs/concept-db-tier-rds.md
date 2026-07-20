# 개념 정리 — DB Tier (RDS · 격리 · 비밀번호 관리)

> `rds.tf` 코드가 무엇을 구성하는지, 그리고 "지하 금고"가 실제로 잠겨있음을 어떻게 검증했는지 정리.

관련 코드: [`rds.tf`](../rds.tf) · 선행: [concept-app-tier-alb.md](concept-app-tier-alb.md)

---

## 1. RDS = 관리형 관계형 데이터베이스

EC2에 직접 MySQL을 설치할 수도 있지만, 그러면 백업·패치·장애복구·모니터링을 전부 직접 해야 한다.
**RDS**는 이를 AWS가 대신 처리하는 관리형 서비스다.

- 자동 백업 / 스냅샷
- 보안 패치 자동 적용
- Multi-AZ 구성 시 장애 발생하면 대기 인스턴스로 자동 전환(failover)

→ "DB 운영 잡무는 AWS가, 우리는 데이터에 집중". 실무에서 DB를 EC2에 직접 올리는 경우는 드물다.

---

## 2. DB 서브넷 그룹 (DB Subnet Group)

RDS는 **자신이 배치될 수 있는 서브넷 목록**을 미리 지정받아야 한다. 그것이 DB 서브넷 그룹이다.

- 이 프로젝트: `db-2a`(10.0.20.0/24) + `db-2c`(10.0.21.0/24)
- **최소 2개 AZ 필수** — 장애 시 다른 AZ로 전환할 수 있어야 하므로 (Multi-AZ를 안 쓰더라도 요구됨)

---

## 3. 보안 사슬의 완성 (3단계 방어)

```
인터넷 ──(80)──▶ [ALB SG] ──(80)──▶ [App SG] ──(3306)──▶ [DB SG]
                                                            ▲
                                            오직 App SG에서 오는 것만 허용
```

- DB는 인터넷은 물론 **ALB에서조차 직접 접근 불가**. 오직 App tier 경유.
- 각 계층이 "바로 앞 계층의 보안그룹"만 출발지로 허용 → **심층 방어(defense in depth)**.

### DB 보안그룹에는 egress(아웃바운드) 규칙이 없다
DB는 스스로 인터넷에 나갈 일이 없으므로 아웃바운드를 전면 차단했다. **최소 권한 원칙**의 적용.
(App SG는 NAT를 통해 패키지를 받아야 하므로 egress를 열어둔 것과 대조)

---

## 4. 비밀번호 관리와 tfstate 주의

```hcl
variable "db_password" {
  type      = string
  sensitive = true   # plan/apply 출력에서 값을 가림
}
```
값은 `.gitignore`된 `terraform.tfvars`에 두고, 코드(.tf)에는 변수로만 참조한다.

### ⚠️ 중요: `sensitive`는 화면 출력만 가린다
비밀번호는 **`terraform.tfstate`에 평문으로 저장된다.**
→ 그래서 프로젝트 시작 시 `.gitignore`에 `*.tfstate`를 넣어둔 것이 여기서 실제로 중요해진다.

### 운영 환경의 더 나은 방법
`manage_master_user_password = true` 를 사용하면 **AWS Secrets Manager**가 비밀번호를 생성·관리하여,
코드에도 state에도 비밀번호가 남지 않는다. 실무에서는 이 방식이 권장된다.

---

## 5. 주요 설정과 트레이드오프

| 설정 | 이 프로젝트 | 운영 환경 정석 | 이유 |
|------|-------------|----------------|------|
| `multi_az` | `false` | `true` | 대기 인스턴스를 다른 AZ에 두면 비용 2배. 학습용은 단일 |
| `publicly_accessible` | `false` | `false` | 인터넷에서 접근 불가 (필수) |
| `skip_final_snapshot` | `true` | `false` | 운영에서 최종 백업 없이 삭제하면 절대 안 됨 |
| `storage_encrypted` | `true` | `true` | 저장 데이터 암호화 |

---

## 6. AWS 리소스 이름 규칙 (실제로 겪은 에러)

apply 전 `terraform plan`에서 다음 에러가 발생했다.

```
Error: first character of "identifier" must be a letter
identifier = "${var.project_name}-db"   →  "3tier-db"
```

- **RDS 식별자·DB 서브넷 그룹 이름은 반드시 문자로 시작**해야 한다.
  프로젝트명이 `3tier`(숫자 시작)이므로 `db-3tier`, `db-subnet-group-3tier`로 접두사를 붙여 해결.
- **교훈:** AWS는 서비스마다 이름 규칙이 다르다(S3 버킷은 전역 유일·소문자, RDS는 문자 시작 등).
  또한 **`terraform plan` 통과가 apply 성공을 보장하지 않는다** — AWS API만 아는 제약은 실제 요청 시 드러난다.

---

## 7. 격리 검증 (실제 확인 결과)

로컬(노트북)에서 RDS 엔드포인트에 접근을 시도했다.

```bash
$ dig +short db-3tier.xxxx.ap-northeast-2.rds.amazonaws.com
10.0.21.34                       # ← db-2c 서브넷(10.0.21.0/24)의 사설 IP

$ nc -zv -w 5 db-3tier.xxxx.ap-northeast-2.rds.amazonaws.com 3306
Operation timed out              # ← 접속 실패 (= 정상)
```

**해석:**
1. 엔드포인트가 **사설 IP(10.0.21.34)** 로 해석됨 → 설계한 DB 서브넷(AZ 2c)에 정확히 배치됨.
   사설 IP이므로 인터넷에서 라우팅 자체가 불가능.
2. 접속 타임아웃 → **외부에서 DB에 도달할 수 없음**을 실증.

**이중 방어 확인:** ① 공인 IP 없음(`publicly_accessible = false`) ② DB SG가 App SG만 허용.

---

## 8. 코드 ↔ 동작 매핑

| Terraform 리소스 | 하는 일 |
|------------------|---------|
| `aws_db_subnet_group.main` | RDS가 배치될 서브넷 목록(db-2a, db-2c) 지정 |
| `aws_security_group.db` | App SG에서 오는 3306만 허용, 아웃바운드 전면 차단 |
| `aws_db_instance.main` | MySQL 8.0 RDS 인스턴스(private, 암호화, 단일 AZ) |

# aws-cloud-pipeline-project
부하분산테스트 

## 시스템 아키텍처
![Architecture](./Architecture/aws-image-pipeline-architecture.png)

# AWS 기반 고가용성 이미지 처리 파이프라인

> Terraform · AWS · GitHub Actions CI/CD 기반 인프라 구성과 비동기 이미지 처리

이미지 업로드 API와 이미지 처리 작업을 분리한 SeSAC 교육 팀 프로젝트.
Terraform으로 AWS 인프라를 구성하고, ALB·Auto Scaling Group으로 API 요청을 분산하며, S3·SQS·Lambda로 이미지 리사이징을 비동기 처리.

| 항목 | 내용 |
| --- | --- |
| 프로젝트 기간 | 2026.03.13 ~ 2026.03.28 — 최종 보고서 수행 일정 기준 |
| 팀 구성 | 4인 팀 |
| 본인 주담당 | GitHub Actions CI/CD 파이프라인 구축·자동화, 모니터링 및 성능 분석 |
| 공동 작업 | Terraform 기반 인프라 구성과 서비스 배포 점검 |
| 주요 기술 | AWS, Terraform, Docker, GitHub Actions, Python, FastAPI, Pillow, k6 |

팀 공동 구현과 본인 담당 범위를 구분해 정리한 저장소.
아래 아키텍처·모듈 설명은 팀 전체 구현 기준. 개인 역할은 최종 보고서의 역할 분담을 기준으로 기재하고, 테스트 기록과 현재 공개 코드의 구현 범위를 구분.

## 1. 시스템 아키텍처

![AWS 이미지 처리 파이프라인 아키텍처](./Architecture/aws-image-pipeline-architecture.png)

```text
사용자 → ALB → EC2 API 컨테이너 / Auto Scaling Group
                    ↓ 이미지 업로드
                  원본 S3 → SQS → Lambda → 처리본 S3
                             └→ 반복 처리 실패 시 DLQ

CloudWatch Alarm → SNS → 알림용 Lambda → Slack
```

- API 계층: FastAPI 컨테이너를 EC2에서 실행하고 ALB로 요청 분산
- 처리 계층: 원본 S3의 `.jpg` 객체 생성 이벤트를 SQS로 전달한 뒤 Lambda에서 640×640 이미지로 변환
- 네트워크: Public Subnet의 ALB와 Private Subnet의 EC2를 분리하고 필요한 AWS 서비스는 VPC Endpoint로 접근
- 운영 계층: CloudWatch 지표·알람, Lambda X-Ray 추적, SNS·Slack 알림 구성

## 2. 주요 설계와 구현

### Terraform 모듈화와 원격 State

- 네트워크, 스토리지, 메시징, Lambda, 컴퓨트 영역을 모듈로 분리
- 모듈 output을 연결해 VPC·Subnet·버킷·큐·ECR 정보를 전달
- S3 원격 State와 DynamoDB 잠금 구성으로 공동 작업 시 상태 관리
- `backend/`에서 State 저장소를 구성하고 `Terraform/`에서 서비스 인프라 관리

구현 근거: [루트 모듈](./Terraform/main.tf) · [Backend 구성](./backend/main.tf) · [State 설정](./Terraform/backend.tf)

### Private Subnet과 VPC Endpoint

- EC2를 Private Subnet에 배치하고 API 요청은 ALB를 통해 전달
- S3 Gateway Endpoint와 STS·ECR·CloudWatch Logs·SSM 계열 Interface Endpoint 구성
- 외부에서 SSH 포트를 개방하는 방식 대신 SSM을 활용한 서버 점검
- Interface Endpoint용 Security Group에 VPC 내부 HTTPS 접근 규칙 구성

구현 근거: [네트워크 모듈](./Terraform/modules/network/main.tf)

### API 확장과 상태 확인

- Launch Template과 Auto Scaling Group으로 API 서버 구성
- ALB 요청 수와 EC2 CPU 사용률을 기준으로 한 확장 정책 구성
- 요청 수 감소에 따른 축소 정책 및 Warm Pool 구성
- EC2 실행 상태와 ALB 대상 그룹의 서비스 정상 상태를 구분해 점검

구현 근거: [Auto Scaling 구성](./Terraform/modules/compute/asg.tf) · [지표와 알람](./Terraform/modules/compute/cw.tf)

보고서에 정리된 정책 변경 방향:

- CPU 사용률만으로 축소 여부를 판단하지 않도록 CPU 기반 Scale-in 정책 제거
- 요청 수 감소 기반 Scale-in을 유지하고 Scale-in cooldown을 180초로 조정
- Scale-out 단위를 1대에서 2대로, 최대 인스턴스 수를 6대에서 8대로 변경
- Stopped 상태의 Warm Pool 인스턴스 2대와 ELB 기반 Health Check 구성

현재 코드에서도 위 설정을 확인할 수 있으며, Warm Pool의 실제 기동 시간 단축 폭은 별도 수치로 단정하지 않음.

### 비동기 이미지 처리와 실패 격리

- API에서 원본 이미지를 S3에 저장하고, 리사이징은 SQS·Lambda 경로로 분리
- Lambda에서 Pillow로 이미지를 변환한 뒤 별도 S3 버킷에 저장
- SQS 재시도 후 DLQ로 실패 메시지를 격리하도록 설정
- S3 테스트 이벤트 등 처리 대상이 아닌 메시지는 건너뛰고, 실제 처리 오류는 다시 발생시켜 재시도 경로 유지

구현 근거: [메시징 모듈](./Terraform/modules/messaging/main.tf) · [Lambda 처리 코드](./app/lambda-func/handler.py)

## 3. 배포 자동화

현재 저장소의 배포 방식은 두 가지로 구분.

| 구분 | 담당 범위 | 관련 파일 |
| --- | --- | --- |
| GitHub Actions | Terraform 검증·Plan·Apply용 워크플로 정의 | [CI](./.github/workflows/terraform-ci.yml) / [CD](./.github/workflows/terraform-cd.yml) |
| 로컬 통합 스크립트 | ECR 생성, Docker 이미지 빌드·Push, 전체 인프라 Apply | [deploy.sh](./deploy.sh) |

`deploy.sh`의 실행 순서:

1. Storage 모듈을 우선 적용해 ECR 리포지토리 생성
2. Terraform output에서 API·Lambda ECR 주소 조회
3. API·Lambda 컨테이너 이미지 빌드 후 ECR에 Push
4. 나머지 네트워크·컴퓨트 등 전체 인프라 적용

GitHub Actions에서 Docker 이미지 빌드까지 수행하는 통합 파이프라인은 현재 구현 범위에 포함하지 않음.

## 4. 모니터링과 성능 분석

- CloudWatch에서 ALB 요청 수, EC2 CPU 사용률, SQS 적체, DLQ 메시지, Lambda 오류를 확인하도록 구성
- CloudWatch Alarm → SNS → Lambda → Slack 알림 경로 구성
- Lambda Active Tracing과 X-Ray 쓰기 권한 설정
- 본인 주담당: 모니터링 구성과 성능 분석, 지표를 기준으로 한 인프라 설정 검토
- 별도 프런트엔드 대신 k6와 CLI를 사용해 이미지 업로드 트래픽 생성

구현 근거: [CloudWatch·알림 구성](./Terraform/modules/compute/cw.tf) · [대시보드](./Terraform/modules/compute/dashboard.tf) · [Lambda 추적 설정](./Terraform/modules/lambda/main.tf)

### 1차 테스트 기록

최종 보고서 2.4.1절에 기재된 결과를 요약. 아래 수치는 보고서 기록이며, 현재 저장소에는 k6 실행 스크립트와 측정 원본이 포함되어 있지 않아 독립적인 재현 검증은 하지 않은 상태.

| 확인 항목 | 보고서 기록 |
| --- | --- |
| 오류 주입 수 / DLQ 격리 메시지 수 | 세 구간에서 각각 156/156, 148/148, 456/456으로 기재 |
| SQS 큐 적체 | 최대 깊이 1,820개로 기재 |
| 확장 지연 | 새 인스턴스 준비와 Health Check 대기 구간을 개선 대상으로 정리 |
| 축소 정책 | 낮은 CPU 사용률만으로 축소되는 상황을 피하도록 정책 재검토 |

보고서의 시나리오 설명과 결과 표에 VU 조건 차이가 있어, p95 응답시간·오류율을 동일 조건의 성능 비교 수치로 제시하지 않음. 오류 주입 수와 DLQ 수의 일치는 기록된 세 구간에 한정하며, 시스템 전체의 무손실이나 중복 없는 처리를 보장하는 의미로 사용하지 않음.

### 2차 테스트 기록

최종 보고서 2.4.3절에 기재된 두 시나리오를 구분해 정리.

| 시나리오 | 보고서에 기재된 입력 조건 | 보고서에 기재된 관찰 결과 |
| --- | --- | --- |
| 요청 수 기반 확장 | VU 200, 800KB 이미지 94%·5MB 이미지 5%·비정상 파일 1% | ALB 요청 수 임계치가 먼저 반응하여 Scale-out |
| CPU 기반 확장 | VU 200, 대용량 이미지를 20MB로 변경 | SHA-512 연산 부하에서 CPU 77.6%, 인스턴스 최대 8대로 확장 |

보고서 회고에는 2차 테스트에서 Ground Truth 오류 주입 로직을 누락했다고 기재되어 있어, 비정상 파일 비율과 DLQ 정합성에 대한 검증 완료를 주장하지 않음. 1차·2차는 입력 조건과 검증 목적이 달라 직접적인 성능 개선율을 계산하지 않음.

## 5. 운영 점검 기준

아래는 구현 구조를 바탕으로 정리한 점검 절차이며, 실제 발생 이력이나 개인 장애 해결 성과를 의미하지 않음.

### EC2 실행 상태와 서비스 상태 구분

1. EC2 Running 여부와 별개로 ALB 대상 그룹 Health Check 확인
2. SSM으로 접속해 `/var/log/cloud-init-output.log`와 컨테이너 상태 점검
3. ECR 이미지 Pull 실패 시 네트워크 경로·DNS·IAM 권한을 각각 확인
4. STS 호출이 있는 인증 경로라면 해당 Endpoint와 권한을 추가 점검
5. 조치 후 컨테이너 상태, ALB Health Check, 실제 API 응답을 각각 확인

### Terraform 공동 작업

- 팀원이 동일한 Backend와 State key를 사용하는지 확인
- 리소스 충돌 시 실제 리소스와 State의 차이를 확인하고 무분별한 삭제·재생성 지양
- 동시 변경 시 State Lock과 작업 주체를 확인한 뒤 진행

### Lambda 이벤트와 처리 실패 구분

- SQS 메시지 body 내부의 S3 이벤트 구조를 확인해 테스트 이벤트와 처리 대상 구분
- 이미지 처리 실패는 예외를 전파해 재시도·DLQ 경로 유지
- 정상 업로드, 테스트 이벤트, 손상 이미지에 대한 기대 결과를 각각 정의
- CloudWatch 오류 호출 수와 DLQ 메시지 수는 재시도와 집계 기준이 다르므로 단순히 동일한 값으로 간주하지 않음

## 6. 디렉터리 구조

```text
.
├── .github/workflows/       # Terraform CI/CD 워크플로
├── Architecture/           # 아키텍처 이미지와 원본
├── Terraform/
│   ├── main.tf             # 모듈 연결
│   ├── backend.tf          # 원격 State 설정
│   └── modules/
│       ├── network/        # VPC, Subnet, VPC Endpoint
│       ├── storage/        # S3, ECR
│       ├── messaging/      # SQS, DLQ, S3 이벤트
│       ├── lambda/         # 이미지 처리 Lambda
│       └── compute/        # ALB, EC2, ASG, 모니터링·알림
├── app/
│   ├── ec2-api/             # FastAPI 업로드 API
│   ├── lambda-func/         # 이미지 리사이징
│   └── slack-notifier/      # Slack 알림
├── backend/                # State용 S3·DynamoDB 구성
└── deploy.sh               # 로컬 통합 배포 스크립트
```

## 7. 실행 전 확인 사항

> 이 저장소의 스크립트와 워크플로는 실제 AWS 리소스를 생성·변경할 수 있으며 비용 발생 가능.
> 포트폴리오 열람에는 실행이 필요하지 않음.

- AWS CLI, Terraform, Docker와 대상 계정의 권한 확인
- `Terraform/backend.tf` 및 `backend/main.tf`의 기존 팀 환경 값을 본인 환경에 맞게 검토
- 원격 State를 사용하는 계정·버킷·잠금 테이블 확인
- AWS 계정 정보와 Slack Webhook 등 민감 값은 커밋하지 않고 별도 관리
- `deploy.sh`는 Storage 선적용과 `-auto-approve`를 포함하므로 실행 전 변경 대상·State·예상 비용 검토
- 현재 Actions는 `main` Push를 트리거로 하므로 README 편집도 배포 실행을 유발할 수 있음. 문서 정리 시 먼저 워크플로 실행 여부 확인

## 8. 현재 한계와 개선 항목

현재 공개 코드는 교육 프로젝트의 구현 기록이며, 아래 항목은 후속 정리 대상.

- CI 작업 경로를 실제 Terraform 디렉터리와 일치시키고 하위 모듈까지 포맷 검사
- CI와 CD에 중복된 Apply 역할을 정리하고, Plan·Apply 실패가 성공으로 처리되지 않도록 실패 전파 개선
- PR 검증과 승인 후 배포를 분리하고 AWS OIDC 인증 적용 검토
- k6 테스트 스크립트·실행 조건·측정 결과를 함께 게시해 검증 재현성 보강

## 기술 스택

| 분야 | 기술 |
| --- | --- |
| Cloud / Network | AWS VPC, Subnet, VPC Endpoint, IAM, SSM |
| Compute | EC2, ALB, Auto Scaling Group, Docker |
| Storage / Messaging | S3, ECR, SQS, DLQ, SNS |
| Image Processing | Lambda, Python, Pillow |
| API | Python, FastAPI |
| IaC / CI/CD | Terraform, GitHub Actions, Shell Script |
| Monitoring / Test | CloudWatch, X-Ray, Slack, k6 |

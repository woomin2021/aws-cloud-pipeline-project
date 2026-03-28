#!/bin/bash
# 에러 발생 시 즉시 중단, 미선언 변수 사용 시 에러, 파이프라인 에러 체크
set -euo pipefail

# 1. 환경 설정
AWS_REGION="ap-northeast-2"

echo "------------------------------------------------"
echo "🚀 AWS Cloud Pipeline 통합 배포를 시작합니다."
echo "------------------------------------------------"

# Step 0: ECR 리포지토리 우선 생성 (storage 모듈)
echo "📦 [Step 0] ECR 리포지토리를 생성 중..."
cd Terraform
terraform init
terraform apply -target=module.storage -auto-approve

# 테라폼 Output에서 실제 주소 동적 추출
# 사용자께서 작성하신 output 명칭을 그대로 사용합니다.
API_ECR_URL=$(terraform output -raw api_ecr_url)
LAMBDA_ECR_URL=$(terraform output -raw lambda_ecr_url)
# ECR 주소에서 베이스 URL(계정ID.dkr.ecr...)만 분리
ECR_BASE=$(echo $API_ECR_URL | cut -d'/' -f1)
cd ..

# Step 1: AWS ECR 로그인
echo "🔐 [Step 1] ECR에 로그인합니다..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_BASE"

# Step 2: API 서버 빌드 및 푸시 (EC2)
echo "🖥️ [Step 2] API 서버(EC2용) 이미지를 빌드 및 푸시합니다..."
cd app/ec2-api
docker build -t api-server .
docker tag api-server:latest "${API_ECR_URL}:latest"
docker push "${API_ECR_URL}:latest"
cd ../..

# Step 3: 이미지 처리기 빌드 및 푸시 (Lambda)
echo "⚡ [Step 3] 이미지 처리기(Lambda용) 이미지를 빌드 및 푸시합니다..."
cd app/lambda-func
# Lambda 환경에 맞춰 플랫폼 지정
docker build --platform linux/amd64 --provenance=false -t lambda-processor .
docker tag lambda-processor:latest "${LAMBDA_ECR_URL}:latest"
docker push "${LAMBDA_ECR_URL}:latest"
cd ../..

# Step 4: 나머지 전체 인프라 배포
echo "🏗️ [Step 4] 전체 AWS 인프라를 구성/업데이트합니다..."
cd Terraform
terraform apply -auto-approve 
cd ..

echo "------------------------------------------------"
echo "✅ 모든 배포가 성공적으로 완료되었습니다!"
echo "------------------------------------------------"
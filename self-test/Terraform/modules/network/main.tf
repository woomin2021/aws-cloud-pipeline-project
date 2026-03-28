# VPC
resource "aws_vpc" "project_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${var.project_name}-vpc" }
}

# igw
resource "aws_internet_gateway" "project_igw" {
  vpc_id = aws_vpc.project_vpc.id
  tags   = { Name = "${var.project_name}-igw" }
}

# public sub
resource "aws_subnet" "public" {
  count             = length(var.public_subnets)
  vpc_id            = aws_vpc.project_vpc.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags              = { Name = "${var.project_name}-public-subnet-${count.index + 1}" }
}

# private sub
resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.project_vpc.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags              = { Name = "${var.project_name}-private-subnet-${count.index + 1}" }
}

# public_rt
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.project_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.project_igw.id
  }
  tags = { Name = "${var.project_name}-public-rt" }
}

# private_rt
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.project_vpc.id
  tags   = { Name = "${var.project_name}-private-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# s3gw
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.project_vpc.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [aws_route_table.private.id]
  tags = { Name = "${var.project_name}-s3-gw-ep" }
}

# Interface Endpoint용 보안그룹 (VPC 내부에서 HTTPS만 허용)
resource "aws_security_group" "vpc_endpoint_sg" {
  name        = "${var.project_name}-vpce-sg"
  description = "Allow HTTPS from within VPC for Interface Endpoints"
  vpc_id      = aws_vpc.project_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${var.project_name}-vpce-sg" }
}

# STS
resource "aws_vpc_endpoint" "sts" {
  vpc_id              = aws_vpc.project_vpc.id
  service_name        = "com.amazonaws.${var.region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = { Name = "${var.project_name}-sts-ep" }
}

# ECR Docker (이미지 pull)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.project_vpc.id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = { Name = "${var.project_name}-ecr-dkr-ep" }
}

# ECR API (이미지 메타데이터 조회)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.project_vpc.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = { Name = "${var.project_name}-ecr-api-ep" }
}

# CloudWatch Logs (Docker 컨테이너 로그)
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.project_vpc.id
  service_name        = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = { Name = "${var.project_name}-logs-ep" }
}

# SSM 관련 엔드포인트 3가지

# ssm
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.project_vpc.id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true
}

# ssmmessages
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.project_vpc.id
  service_name        = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true
}

# ec2messages
resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.project_vpc.id
  service_name        = "com.amazonaws.${var.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true
}
# 1. ALB를 위한 보안 그룹
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP traffic to ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# 2. EC2 인스턴스를 위한 보안 그룹
resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Allow traffic only from ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-ec2-sg" }
}

#3. k6 부하 테스트 를 위한 보안 그룹
resource "aws_security_group" "k6_sg" {
  name        = "${var.project_name}-k6-sg"
  description = "Security group for k6 load tester"
  vpc_id      = var.vpc_id

  # 3-1. SSH 접속: 내 PC에서만 접속 가능하도록 설정
  ingress {
    description = "Allow SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    # 현재는 테스트 용으로 0.0.0.0/0으로 해놨는데 공인 IP로 특정해보고 싶음
    cidr_blocks = ["0.0.0.0/0"] 
  }

  # 3-2. 아웃바운드: k6 패키지 설치 및 ALB 호출을 위해 전체 개방
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # 모든 프로토콜
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-k6-sg"
  }
}
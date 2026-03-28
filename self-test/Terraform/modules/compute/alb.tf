# 1. 로드밸런서(ALB) 본체 생성
resource "aws_lb" "this" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id] # sg.tf에 있는 ID를 자동으로 참조
  subnets            = var.public_subnet_ids

  tags = { Name = "${var.project_name}-alb" }
}

# 2. 대상 그룹(Target Group) 생성
resource "aws_lb_target_group" "this" {
  name        = "${var.project_name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-299"
    interval            = 30
    timeout             = 15 #5 → 15초
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# 3. 리스너(Listener) 설정
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
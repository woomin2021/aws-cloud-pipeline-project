data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

resource "aws_launch_template" "this" {
  name_prefix   = "${var.project_name}-tpl-"
  image_id      = data.aws_ssm_parameter.ecs_optimized_ami.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ec2-user

    # ECR credential helper 설정 (AWS CLI 없이 ECR 인증)
    mkdir -p /root/.docker
    cat <<'DOCKER_CONFIG' > /root/.docker/config.json
    {
      "credHelpers": {
        "670801933625.dkr.ecr.ap-northeast-2.amazonaws.com": "ecr-login"
      }
    }
    DOCKER_CONFIG

    # docker-credential-ecr-login 설치
    yum install -y amazon-ecr-credential-helper

    docker pull ${var.api_ecr_url}:latest

    docker run -d -p 80:80 \
      -e S3_BUCKET_NAME=${var.source_bucket_id} \
      -e AWS_REGION=ap-northeast-2 \
      ${var.api_ecr_url}:latest
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "${var.project_name}-ec2" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "this" {
  name = "${var.project_name}-asg"

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  vpc_zone_identifier = var.private_subnet_ids

  min_size         = 2
  max_size         = 8  # 6 → 8 (AZ 2개 기준 3번 스케일아웃 가능)
  desired_capacity = 2

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances",
    "GroupMinSize",
    "GroupMaxSize"
  ]

  target_group_arns = [aws_lb_target_group.this.arn]

  health_check_type         = "EC2"
  health_check_grace_period = 180

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-instance"
    propagate_at_launch = true
  }

  instance_refresh {
    strategy = "Rolling"
  }


}

# 스케일아웃 정책1 : ALB 기반 (선제적)
resource "aws_autoscaling_policy" "scale_out_by_request" {
  name                   = "${var.project_name}-scale-out-request"
  autoscaling_group_name = aws_autoscaling_group.this.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 2
  cooldown               = 60
  policy_type            = "SimpleScaling"
}

# 스케일아웃 정책2 : CPU 기반 (방어적)
resource "aws_autoscaling_policy" "scale_out_by_cpu" {
  name                   = "${var.project_name}-scale-out-cpu"
  autoscaling_group_name = aws_autoscaling_group.this.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 2
  cooldown               = 60
  policy_type            = "SimpleScaling"
}

# 스케일인 정책 : ALB 요청 수 감소 시
resource "aws_autoscaling_policy" "scale_in_by_request" {
  name                   = "${var.project_name}-scale-in-request"
  autoscaling_group_name = aws_autoscaling_group.this.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 180  # 300 → 180초
  policy_type            = "SimpleScaling"
}
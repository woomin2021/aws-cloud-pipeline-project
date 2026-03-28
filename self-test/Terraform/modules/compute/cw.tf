# ALB 요청 수 증가 → 스케일아웃
resource "aws_cloudwatch_metric_alarm" "high_requests" {
  alarm_name          = "${var.project_name}-high-requests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "RequestCountPerTarget"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "300"  # 50 → 300

  dimensions = {
    TargetGroup  = aws_lb_target_group.this.arn_suffix
    LoadBalancer = aws_lb.this.arn_suffix
  }

  alarm_actions = [aws_autoscaling_policy.scale_out_by_request.arn]
  ok_actions    = [aws_autoscaling_policy.scale_in_by_request.arn]
}

# CPU 사용량 증가 → 스케일아웃
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "5"   # 2 → 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "60"  # 80 → 60

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_out_by_cpu.arn]
}

# ALB 요청 수 감소 → 스케일인
resource "aws_cloudwatch_metric_alarm" "low_requests" {
  alarm_name          = "${var.project_name}-low-requests"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RequestCountPerTarget"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "10"

  dimensions = {
    TargetGroup  = aws_lb_target_group.this.arn_suffix
    LoadBalancer = aws_lb.this.arn_suffix
  }

  alarm_actions = [aws_autoscaling_policy.scale_in_by_request.arn]
}
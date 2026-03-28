output "alb_dns_name" {
  description = "로드밸런서의 주소입니당"
  value       = aws_lb.this.dns_name
}
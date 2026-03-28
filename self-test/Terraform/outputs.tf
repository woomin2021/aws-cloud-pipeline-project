output "alb_dns_name" {
  description = "로드밸런서 주소"
  value       = module.compute.alb_dns_name
}
variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project_name" {
  type    = string
  default = "self-test"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "api_ecr_url" {
  description = "개인 계정 ECR 주소"
  type        = string
}

variable "source_bucket_id" {
  description = "S3 버킷 이름"
  type        = string
}

variable "source_bucket_arn" {
  description = "S3 버킷 ARN"
  type        = string
}
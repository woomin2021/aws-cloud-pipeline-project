variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "project_name" {
  type    = string
  default = "self-test"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "api_ecr_url" {
  type = string
}

variable "source_bucket_id" {
  type = string
}

variable "source_bucket_arn" {
  type = string
}
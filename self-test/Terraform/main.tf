module "network" {
  source = "./modules/network"

  project_name       = var.project_name
  region             = var.aws_region
  vpc_cidr           = var.vpc_cidr
  public_subnets     = var.public_subnets
  private_subnets    = var.private_subnets
  availability_zones = var.availability_zones
}

module "compute" {
  source        = "./modules/compute"
  project_name  = var.project_name
  instance_type = var.instance_type

  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids

  api_ecr_url       = var.api_ecr_url
  source_bucket_id  = var.source_bucket_id
  source_bucket_arn = var.source_bucket_arn
}
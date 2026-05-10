####################################################################
# dev environment — wires all modules together
####################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  name = "${var.project}-${var.environment}"
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ---------- Networking ----------
module "vpc" {
  source = "../../modules/vpc"

  name               = local.name
  cidr_block         = var.vpc_cidr
  az_count           = 2
  single_nat_gateway = true # cheaper for dev; flip to false in prod
  tags               = local.common_tags
}

# ---------- ALB ----------
module "alb" {
  source = "../../modules/alb"

  name                = local.name
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  target_port         = 3000
  health_check_path   = "/healthz"
  certificate_arn     = var.acm_certificate_arn
  deletion_protection = false
  tags                = local.common_tags
}

# ---------- S3 (static assets) ----------
module "s3" {
  source = "../../modules/s3"

  bucket_name         = "${local.name}-assets-${data.aws_caller_identity.current.account_id}"
  deletion_protection = false
  tags                = local.common_tags
}

data "aws_caller_identity" "current" {}

# ---------- ECS service (creates the app SG used by RDS) ----------
module "ecs" {
  source = "../../modules/ecs"

  name                  = local.name
  region                = var.region
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_app_subnet_ids
  alb_security_group_id = module.alb.security_group_id
  target_group_arn      = module.alb.target_group_arn

  container_port = 3000
  image_tag      = var.image_tag

  task_cpu      = 256
  task_memory   = 512
  desired_count = 2
  min_capacity  = 2
  max_capacity  = 4

  db_secret_arn = module.rds.secret_arn
  s3_bucket_arn = module.s3.bucket_arn

  log_retention_days = 30
  tags               = local.common_tags
}

# ---------- RDS ----------
module "rds" {
  source = "../../modules/rds"

  name                  = local.name
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.private_data_subnet_ids
  app_security_group_id = module.ecs.app_security_group_id

  db_name        = "todos"
  db_username    = "todo_app"
  engine_version = "16.4"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 50

  multi_az                = false # cheaper for dev
  backup_retention_period = 7
  deletion_protection     = false

  tags = local.common_tags
}

# ---------- Monitoring ----------
module "monitoring" {
  source = "../../modules/monitoring"

  name                    = local.name
  ecs_cluster_name        = module.ecs.cluster_name
  ecs_service_name        = module.ecs.service_name
  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  rds_instance_id         = module.rds.instance_id
  app_log_group_name      = module.ecs.log_group_name
  min_running_tasks       = 2
  alert_email_addresses   = var.alert_emails

  tags = local.common_tags
}

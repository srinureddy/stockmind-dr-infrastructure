locals {
  name = "${var.project}-dr"
}

# ── 1. DR Network ────────────────────────────────────────────────────────────
module "dr_network" {
  source    = "./modules/dr_network"
  providers = { aws = aws.dr }
  name        = local.name
  project     = var.project
  environment = var.environment
  vpc_cidr    = var.dr_vpc_cidr
  azs         = var.dr_azs
}

# ── 2. DR Compute (Pilot Light) ──────────────────────────────────────────────
module "dr_compute" {
  source    = "./modules/dr_compute"
  providers = { aws = aws.dr }

  name                   = local.name
  project                = var.project
  environment            = var.environment
  dr_region              = var.dr_region
  primary_region         = var.primary_region
  dr_strategy            = var.dr_strategy
  warm_standby_min_count = var.warm_standby_min_count

  # Network
  vpc_id            = module.dr_network.vpc_id
  public_subnet_ids = module.dr_network.public_subnet_ids
  app_subnet_ids    = module.dr_network.app_subnet_ids
  data_subnet_ids   = module.dr_network.data_subnet_ids
  alb_sg_id         = module.dr_network.alb_sg_id
  frontend_sg_id    = module.dr_network.frontend_sg_id
  backend_sg_id     = module.dr_network.backend_sg_id
  worker_sg_id      = module.dr_network.worker_sg_id
  timescale_sg_id   = module.dr_network.timescale_sg_id
  redis_sg_id       = module.dr_network.redis_sg_id

  # TimescaleDB
  timescale_ami_id        = var.timescale_ami_id_dr
  timescale_instance_type = var.timescale_instance_type
  timescale_volume_size   = var.timescale_volume_size
  timescale_image         = var.timescale_image
  timescale_db_name       = var.timescale_db_name
  timescale_db_user       = var.timescale_db_user

  # Images
  frontend_image_tag = var.frontend_image_tag
  backend_image_tag  = var.backend_image_tag
  worker_image_tag   = var.worker_image_tag
  beat_image_tag     = var.beat_image_tag

  # Sizing
  frontend_cpu    = var.frontend_cpu
  frontend_memory = var.frontend_memory
  backend_cpu     = var.backend_cpu
  backend_memory  = var.backend_memory
  worker_cpu      = var.worker_cpu
  worker_memory   = var.worker_memory
  beat_cpu        = var.beat_cpu
  beat_memory     = var.beat_memory

  # Domains
  domain_name     = var.domain_name
  api_domain_name = var.api_domain_name

  # Secrets
  db_password          = var.db_password
  jwt_secret           = var.jwt_secret
  encryption_key       = var.encryption_key
  upstox_client_id     = var.upstox_client_id
  upstox_client_secret = var.upstox_client_secret
  upstox_access_token  = var.upstox_access_token
  redis_auth_token     = var.redis_auth_token
}

# ── 3. DR Data Replication ───────────────────────────────────────────────────
module "dr_data" {
  source = "./modules/dr_data"
  providers = {
    aws.primary = aws.primary
    aws.dr      = aws.dr
  }

  name           = local.name
  project        = var.project
  primary_region = var.primary_region
  dr_region      = var.dr_region

  primary_s3_bucket_name = var.primary_s3_bucket
  primary_s3_bucket_arn  = "arn:aws:s3:::${var.primary_s3_bucket}"
  dr_s3_bucket_name      = module.dr_compute.s3_bucket_name
  dr_s3_bucket_arn       = module.dr_compute.s3_bucket_arn
  primary_ecr_repo_arns  = []   # ECR replication is account-level; no per-repo ARN needed
}

# ── 4. DR Routing (Route53 Failover) ────────────────────────────────────────
module "dr_routing" {
  source = "./modules/dr_routing"
  providers = {
    aws            = aws.primary
    aws.us_east_1  = aws.us_east_1
  }

  name            = local.name
  project         = var.project
  primary_region  = var.primary_region
  dr_region       = var.dr_region
  hosted_zone_id  = var.route53_zone_id
  domain_name     = var.domain_name
  api_domain_name = var.api_domain_name

  primary_alb_dns     = var.primary_alb_dns
  primary_alb_zone_id = var.primary_alb_zone_id
  dr_alb_dns          = module.dr_compute.alb_dns_name
  dr_alb_zone_id      = module.dr_compute.alb_zone_id
  alert_sns_arn       = module.dr_automation.sns_topic_arn
}

# ── 5. DR Automation (Lambda Failover + Alarms) ──────────────────────────────
module "dr_automation" {
  source    = "./modules/dr_automation"
  providers = { aws = aws.dr }

  name           = local.name
  project        = var.project
  dr_region      = var.dr_region
  primary_region = var.primary_region

  ecs_cluster_name      = module.dr_compute.ecs_cluster_name
  frontend_service_name = module.dr_compute.frontend_service_name
  backend_service_name  = module.dr_compute.backend_service_name
  worker_service_name   = module.dr_compute.worker_service_name
  beat_service_name     = module.dr_compute.beat_service_name
  timescale_instance_id = module.dr_compute.timescale_id

  frontend_desired = 2
  backend_desired  = 2
  worker_desired   = 2
  beat_desired     = 1

  health_check_alarm_arn = module.dr_routing.health_check_alarm_arn
  alert_email            = var.alert_email
}

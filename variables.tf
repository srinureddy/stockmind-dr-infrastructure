# ── Identity ────────────────────────────────────────────────────────────────
variable "project" {
  type    = string
  default = "stockmind"
}
variable "environment" {
  type    = string
  default = "prod"
}

# ── Regions ─────────────────────────────────────────────────────────────────
variable "primary_region" {
  type        = string
  default     = "ap-south-2"
  description = "Primary AWS region (Hyderabad)."
}
variable "dr_region" {
  type        = string
  default     = "ap-south-1"
  description = "Disaster Recovery region (Mumbai). Closest Indian region to primary."
}

# ── Availability Zones ──────────────────────────────────────────────────────
variable "primary_azs" {
  type    = list(string)
  default = ["ap-south-2a", "ap-south-2b"]
}
variable "dr_azs" {
  type    = list(string)
  default = ["ap-south-1a", "ap-south-1b"]
}

# ── Networking ───────────────────────────────────────────────────────────────
variable "primary_vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
  description = "Must match the existing primary VPC CIDR."
}
variable "dr_vpc_cidr" {
  type    = string
  default = "10.50.0.0/16"
  description = "DR VPC CIDR — must not overlap with primary."
}

# ── Primary resource references ──────────────────────────────────────────────
variable "primary_alb_dns" {
  type        = string
  description = "DNS name of the primary ALB (from production_stack output: alb_dns_name)."
}
variable "primary_alb_zone_id" {
  type        = string
  description = "Hosted zone ID of the primary ALB (from AWS Console or terraform output)."
}
variable "primary_s3_bucket" {
  type        = string
  description = "Name of the primary S3 artifacts bucket (stockmind-prod-<account_id>-artifacts)."
}
variable "primary_ecr_registry_id" {
  type        = string
  description = "AWS account ID (also the ECR registry ID)."
}

# ── DNS ──────────────────────────────────────────────────────────────────────
variable "domain_name" {
  type    = string
  default = "stockmindai.xyz"
}
variable "api_domain_name" {
  type    = string
  default = "api.stockmindai.xyz"
}
variable "route53_zone_id" {
  type        = string
  description = "Route 53 hosted zone ID for the domain. Required for DNS failover."
}

# ── DR Compute ───────────────────────────────────────────────────────────────
variable "timescale_ami_id_dr" {
  type        = string
  description = "Amazon Linux 2023 AMI in ap-south-1 (query SSM: /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64)."
}
variable "timescale_instance_type" {
  type    = string
  default = "m6i.large"
}
variable "timescale_volume_size" {
  type    = number
  default = 200
}
variable "timescale_image" {
  type        = string
  description = "Pinned TimescaleDB Docker image tag/digest."
}
variable "timescale_db_name" {
  type    = string
  default = "stockmind"
}
variable "timescale_db_user" {
  type    = string
  default = "stockmind"
}

# ── Container image tags ─────────────────────────────────────────────────────
variable "frontend_image_tag" { type = string; default = "v1" }
variable "backend_image_tag"  { type = string; default = "v1" }
variable "worker_image_tag"   { type = string; default = "v1" }
variable "beat_image_tag"     { type = string; default = "v1" }

# ── ECS sizing ───────────────────────────────────────────────────────────────
variable "frontend_cpu"    { type = number; default = 512  }
variable "frontend_memory" { type = number; default = 1024 }
variable "backend_cpu"     { type = number; default = 1024 }
variable "backend_memory"  { type = number; default = 2048 }
variable "worker_cpu"      { type = number; default = 2048 }
variable "worker_memory"   { type = number; default = 4096 }
variable "beat_cpu"        { type = number; default = 256  }
variable "beat_memory"     { type = number; default = 512  }

# ── Secrets (must match values in primary region) ────────────────────────────
variable "db_password"          { type = string; sensitive = true }
variable "jwt_secret"           { type = string; sensitive = true }
variable "encryption_key"       { type = string; sensitive = true }
variable "upstox_client_id"     { type = string; sensitive = true }
variable "upstox_client_secret" { type = string; sensitive = true }
variable "upstox_access_token"  { type = string; sensitive = true; default = "" }
variable "redis_auth_token"     { type = string; sensitive = true }

# ── Monitoring ───────────────────────────────────────────────────────────────
variable "alert_email" {
  type        = string
  description = "Email address for DR failover alerts."
}

# ── DR Strategy ──────────────────────────────────────────────────────────────
variable "dr_strategy" {
  type        = string
  default     = "pilot_light"
  description = "DR strategy: pilot_light (ECS at 0, EC2 stopped) or warm_standby (minimal live instances)."
  validation {
    condition     = contains(["pilot_light", "warm_standby"], var.dr_strategy)
    error_message = "Must be pilot_light or warm_standby."
  }
}
variable "warm_standby_min_count" {
  type        = number
  default     = 1
  description = "Minimum ECS task count in warm_standby mode. Ignored in pilot_light."
}

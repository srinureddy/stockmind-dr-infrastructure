variable "name"            { type = string }
variable "project"         { type = string }
variable "environment"     { type = string }
variable "dr_region"       { type = string }
variable "primary_region"  { type = string }
variable "dr_strategy"     { type = string }
variable "warm_standby_min_count" { type = number }

variable "vpc_id"            { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "app_subnet_ids"    { type = list(string) }
variable "data_subnet_ids"   { type = list(string) }
variable "alb_sg_id"         { type = string }
variable "frontend_sg_id"    { type = string }
variable "backend_sg_id"     { type = string }
variable "worker_sg_id"      { type = string }
variable "timescale_sg_id"   { type = string }
variable "redis_sg_id"       { type = string }

variable "timescale_ami_id"       { type = string }
variable "timescale_instance_type" { type = string }
variable "timescale_volume_size"   { type = number }
variable "timescale_image"         { type = string }
variable "timescale_db_name"       { type = string }
variable "timescale_db_user"       { type = string }

variable "frontend_image_tag" { type = string }
variable "backend_image_tag"  { type = string }
variable "worker_image_tag"   { type = string }
variable "beat_image_tag"     { type = string }

variable "frontend_cpu"    { type = number }
variable "frontend_memory" { type = number }
variable "backend_cpu"     { type = number }
variable "backend_memory"  { type = number }
variable "worker_cpu"      { type = number }
variable "worker_memory"   { type = number }
variable "beat_cpu"        { type = number }
variable "beat_memory"     { type = number }

variable "domain_name"     { type = string }
variable "api_domain_name" { type = string }

variable "db_password"          { type = string; sensitive = true }
variable "jwt_secret"           { type = string; sensitive = true }
variable "encryption_key"       { type = string; sensitive = true }
variable "upstox_client_id"     { type = string; sensitive = true }
variable "upstox_client_secret" { type = string; sensitive = true }
variable "upstox_access_token"  { type = string; sensitive = true }
variable "redis_auth_token"     { type = string; sensitive = true }

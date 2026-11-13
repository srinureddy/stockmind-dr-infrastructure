variable "name"           { type = string }
variable "project"        { type = string }
variable "primary_region" { type = string }
variable "dr_region"      { type = string }

variable "hosted_zone_id"  { type = string; description = "Route53 hosted zone ID for stockmindai.xyz" }
variable "domain_name"     { type = string }
variable "api_domain_name" { type = string }

variable "primary_alb_dns"     { type = string }
variable "primary_alb_zone_id" { type = string }

variable "dr_alb_dns"     { type = string }
variable "dr_alb_zone_id" { type = string }

variable "health_check_path"               { type = string; default = "/health" }
variable "health_check_failure_threshold"  { type = number; default = 3 }
variable "health_check_request_interval"   { type = number; default = 30 }
variable "alert_sns_arn"                   { type = string }

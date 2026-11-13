variable "name"           { type = string }
variable "project"        { type = string }
variable "dr_region"      { type = string }
variable "primary_region" { type = string }

variable "ecs_cluster_name"       { type = string }
variable "frontend_service_name"  { type = string }
variable "backend_service_name"   { type = string }
variable "worker_service_name"    { type = string }
variable "beat_service_name"      { type = string }
variable "timescale_instance_id"  { type = string }

variable "frontend_desired" { type = number; default = 2 }
variable "backend_desired"  { type = number; default = 2 }
variable "worker_desired"   { type = number; default = 2 }
variable "beat_desired"     { type = number; default = 1 }

variable "health_check_alarm_arn" { type = string }
variable "alert_email"            { type = string }

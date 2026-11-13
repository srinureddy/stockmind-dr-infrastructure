variable "name"           { type = string }
variable "project"        { type = string }
variable "primary_region" { type = string }
variable "dr_region"      { type = string }

variable "primary_s3_bucket_arn"  { type = string }
variable "primary_s3_bucket_name" { type = string }
variable "dr_s3_bucket_arn"       { type = string }
variable "dr_s3_bucket_name"      { type = string }

variable "primary_ecr_repo_arns" {
  type        = list(string)
  description = "ARNs of ECR repos in primary region to replicate from"
}

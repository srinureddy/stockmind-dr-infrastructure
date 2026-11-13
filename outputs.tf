output "dr_vpc_id"            { value = module.dr_network.vpc_id }
output "dr_alb_dns_name"      { value = module.dr_compute.alb_dns_name }
output "dr_ecs_cluster"       { value = module.dr_compute.ecs_cluster_name }
output "dr_timescale_id"      { value = module.dr_compute.timescale_id }
output "dr_ecr_urls"          { value = module.dr_compute.ecr_urls }
output "dr_s3_bucket"         { value = module.dr_compute.s3_bucket_name }
output "dr_redis_endpoint"    { value = module.dr_compute.redis_endpoint }
output "health_check_id"      { value = module.dr_routing.health_check_id }
output "failover_lambda_arn"  { value = module.dr_automation.lambda_function_arn }
output "alert_sns_topic_arn"  { value = module.dr_automation.sns_topic_arn }
output "dashboard_url"        { value = module.dr_automation.dashboard_url }

output "rto_summary" {
  value = {
    az_failure       = "0 min  — multi-AZ active in DR (ECS Fargate, Redis Multi-AZ)"
    region_failure   = "15-20 min — Lambda scales pilot-light ECS + starts TimescaleDB EC2"
    db_corruption    = "30-60 min — restore from latest cross-region EBS snapshot in DR vault"
    redis_failure    = "1-5 min — ElastiCache auto-failover to replica node"
    secret_breach    = "5 min — rotate secret in Secrets Manager + force ECS service redeploy"
    image_corruption = "0 min — immutable ECR tags + cross-region replication prevents gaps"
    network_outage   = "2-5 min — Route53 health check detects failure, DNS flips to DR ALB"
  }
}

output "cost_dr_monthly_usd" {
  description = "Estimated monthly DR standby cost (pilot_light strategy, ap-south-1)"
  value = {
    nat_gateway         = "~$32  (1x NAT vs 2x in primary)"
    timescale_ebs_200gb = "~$16  (stopped EC2 — only EBS gp3 charged)"
    redis_t4g_micro     = "~$12  (single-node cache.t4g.micro)"
    alb_idle            = "~$18  (ALB base charge even at 0 requests)"
    ecr_storage         = "~$2   (10 images × 4 services)"
    backup_snapshots    = "~$8   (14-day EBS snapshots in DR vault)"
    s3_replica          = "~$3   (CRR storage + replication requests)"
    lambda_route53      = "~$1   (health checks + Lambda invocations)"
    total               = "~$92/month standby (vs ~$0 with no DR at all)"
  }
}

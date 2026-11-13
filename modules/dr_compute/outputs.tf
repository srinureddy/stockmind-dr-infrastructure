output "alb_dns_name"       { value = aws_lb.dr.dns_name }
output "alb_zone_id"        { value = aws_lb.dr.zone_id }
output "alb_arn"            { value = aws_lb.dr.arn }
output "timescale_id"       { value = aws_instance.timescale.id }
output "timescale_private_dns" { value = aws_instance.timescale.private_dns }
output "s3_bucket_name"     { value = aws_s3_bucket.dr.bucket }
output "s3_bucket_arn"      { value = aws_s3_bucket.dr.arn }
output "ecs_cluster_name"   { value = aws_ecs_cluster.dr.name }
output "ecs_cluster_arn"    { value = aws_ecs_cluster.dr.arn }
output "frontend_service_name" { value = aws_ecs_service.frontend.name }
output "backend_service_name"  { value = aws_ecs_service.backend.name }
output "worker_service_name"   { value = aws_ecs_service.worker.name }
output "beat_service_name"     { value = aws_ecs_service.beat.name }
output "ecr_urls" {
  value = { for k, v in aws_ecr_repository.dr : k => v.repository_url }
}
output "redis_endpoint" { value = aws_elasticache_replication_group.redis.primary_endpoint_address }

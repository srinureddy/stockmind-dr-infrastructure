output "health_check_id"        { value = aws_route53_health_check.primary_api.id }
output "health_check_alarm_arn" { value = aws_cloudwatch_metric_alarm.primary_unhealthy.arn }
output "frontend_dr_fqdn"       { value = aws_route53_record.frontend_dr.fqdn }
output "api_dr_fqdn"            { value = aws_route53_record.api_dr.fqdn }

output "sns_topic_arn"       { value = aws_sns_topic.dr_alerts.arn }
output "lambda_function_arn" { value = aws_lambda_function.failover.arn }
output "eventbridge_rule_arn" { value = aws_cloudwatch_event_rule.health_check_alarm.arn }
output "dashboard_url" {
  value = "https://${var.dr_region}.console.aws.amazon.com/cloudwatch/home?region=${var.dr_region}#dashboards:name=${aws_cloudwatch_dashboard.dr.dashboard_name}"
}

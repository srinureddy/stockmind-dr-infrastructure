# ── Route53 health check on the PRIMARY ALB ───────────────────────────────────
# Health checks run from us-east-1 by design (AWS Route53 uses global PoPs).
# CloudWatch alarms on health checks must also be in us-east-1.

resource "aws_route53_health_check" "primary_api" {
  fqdn              = var.primary_alb_dns
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  failure_threshold = var.health_check_failure_threshold
  request_interval  = var.health_check_request_interval
  measure_latency   = true
  tags              = { Name = "${var.name}-primary-api-hc" }
}

resource "aws_route53_health_check" "primary_frontend" {
  fqdn              = var.primary_alb_dns
  port              = 443
  type              = "HTTPS"
  resource_path     = "/"
  failure_threshold = var.health_check_failure_threshold
  request_interval  = var.health_check_request_interval
  measure_latency   = true
  tags              = { Name = "${var.name}-primary-frontend-hc" }
}

# ── CloudWatch alarm on health check (must be in us-east-1) ──────────────────
resource "aws_cloudwatch_metric_alarm" "primary_unhealthy" {
  provider            = aws.us_east_1
  alarm_name          = "${var.name}-primary-region-unhealthy"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "Primary region ALB health check failed — DR failover required"
  alarm_actions       = [var.alert_sns_arn]
  ok_actions          = [var.alert_sns_arn]
  dimensions          = { HealthCheckId = aws_route53_health_check.primary_api.id }
}

# ── DNS failover records for stockmindai.xyz (frontend) ───────────────────────
resource "aws_route53_record" "frontend_primary" {
  zone_id        = var.hosted_zone_id
  name           = var.domain_name
  type           = "A"
  set_identifier = "primary"

  alias {
    name                   = var.primary_alb_dns
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }
  failover_routing_policy { type = "PRIMARY" }
  health_check_id = aws_route53_health_check.primary_frontend.id
}

resource "aws_route53_record" "frontend_dr" {
  zone_id        = var.hosted_zone_id
  name           = var.domain_name
  type           = "A"
  set_identifier = "dr"

  alias {
    name                   = var.dr_alb_dns
    zone_id                = var.dr_alb_zone_id
    evaluate_target_health = true
  }
  failover_routing_policy { type = "SECONDARY" }
}

# ── DNS failover records for api.stockmindai.xyz (backend) ────────────────────
resource "aws_route53_record" "api_primary" {
  zone_id        = var.hosted_zone_id
  name           = var.api_domain_name
  type           = "A"
  set_identifier = "primary"

  alias {
    name                   = var.primary_alb_dns
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }
  failover_routing_policy { type = "PRIMARY" }
  health_check_id = aws_route53_health_check.primary_api.id
}

resource "aws_route53_record" "api_dr" {
  zone_id        = var.hosted_zone_id
  name           = var.api_domain_name
  type           = "A"
  set_identifier = "dr"

  alias {
    name                   = var.dr_alb_dns
    zone_id                = var.dr_alb_zone_id
    evaluate_target_health = true
  }
  failover_routing_policy { type = "SECONDARY" }
}

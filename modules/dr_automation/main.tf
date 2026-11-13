locals {
  services_json = jsonencode({
    frontend = { name = var.frontend_service_name; desired = var.frontend_desired }
    backend  = { name = var.backend_service_name;  desired = var.backend_desired  }
    worker   = { name = var.worker_service_name;   desired = var.worker_desired   }
    beat     = { name = var.beat_service_name;     desired = var.beat_desired     }
  })
}

# ── SNS topic for DR alerts ───────────────────────────────────────────────────
resource "aws_sns_topic" "dr_alerts" {
  name = "${var.name}-alerts"
}
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.dr_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── Lambda IAM ────────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions    = ["sts:AssumeRole"]
    principals { type = "Service"; identifiers = ["lambda.amazonaws.com"] }
  }
}
resource "aws_iam_role" "failover_lambda" {
  name               = "${var.name}-failover-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.failover_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "failover_policy" {
  name = "${var.name}-failover-policy"
  role = aws_iam_role.failover_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:StartInstances", "ec2:DescribeInstances", "ec2:DescribeInstanceStatus"]
        Resource = ["arn:aws:ec2:${var.dr_region}:*:instance/${var.timescale_instance_id}"]
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = ["arn:aws:ecs:${var.dr_region}:*:service/${var.ecs_cluster_name}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [aws_sns_topic.dr_alerts.arn]
      }
    ]
  })
}

# ── Lambda package — zip the Python file ──────────────────────────────────────
data "archive_file" "failover" {
  type        = "zip"
  source_file = "${path.module}/failover.py"
  output_path = "${path.module}/lambda_package/failover.zip"
}

resource "aws_lambda_function" "failover" {
  function_name    = "${var.name}-failover"
  filename         = data.archive_file.failover.output_path
  source_code_hash = data.archive_file.failover.output_base64sha256
  handler          = "failover.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.failover_lambda.arn
  timeout          = 300   # 5 minutes — EC2 start can be slow
  memory_size      = 256

  environment {
    variables = {
      DR_REGION            = var.dr_region
      ECS_CLUSTER          = var.ecs_cluster_name
      TIMESCALE_INSTANCE_ID = var.timescale_instance_id
      SNS_TOPIC_ARN        = aws_sns_topic.dr_alerts.arn
      SERVICES_JSON        = local.services_json
    }
  }
}

resource "aws_cloudwatch_log_group" "failover_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.failover.function_name}"
  retention_in_days = 30
}

# ── EventBridge rule — fires when health check alarm enters ALARM state ────────
resource "aws_cloudwatch_event_rule" "health_check_alarm" {
  name        = "${var.name}-health-check-alarm"
  description = "Trigger DR failover Lambda when primary region health check fails"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      state = { value = ["ALARM"] }
      alarmName = [{ prefix = "${var.name}-primary-region" }]
    }
  })
}

resource "aws_cloudwatch_event_target" "failover_lambda" {
  rule      = aws_cloudwatch_event_rule.health_check_alarm.name
  target_id = "FailoverLambda"
  arn       = aws_lambda_function.failover.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.failover.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.health_check_alarm.arn
}

# ── CloudWatch Dashboard for DR status ────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "dr" {
  dashboard_name = "${var.name}-overview"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"; x = 0; y = 0; width = 12; height = 6
        properties = {
          title  = "Route53 Health Check"
          region = "us-east-1"
          metrics = [["AWS/Route53", "HealthCheckStatus", "HealthCheckId", "PLACEHOLDER"]]
          view   = "timeSeries"; stat = "Minimum"; period = 60
        }
      },
      {
        type = "metric"; x = 12; y = 0; width = 12; height = 6
        properties = {
          title  = "DR ECS Service Running Tasks"
          region = var.dr_region
          metrics = [
            ["AWS/ECS", "RunningTaskCount", "ServiceName", var.frontend_service_name, "ClusterName", var.ecs_cluster_name],
            ["AWS/ECS", "RunningTaskCount", "ServiceName", var.backend_service_name,  "ClusterName", var.ecs_cluster_name],
            ["AWS/ECS", "RunningTaskCount", "ServiceName", var.worker_service_name,   "ClusterName", var.ecs_cluster_name]
          ]
          view = "timeSeries"; stat = "Average"; period = 60
        }
      }
    ]
  })
}

locals {
  # Pilot light: ECS at 0, EC2 stopped.  Warm standby: minimal live.
  desired = var.dr_strategy == "pilot_light" ? 0 : var.warm_standby_min_count

  ecr_names = {
    frontend = "${var.project}/frontend"
    backend  = "${var.project}/backend"
    worker   = "${var.project}/celery-worker"
    beat     = "${var.project}/celery-beat"
  }
}

data "aws_caller_identity" "current" {}

# ── ECR — replica repos in DR region ─────────────────────────────────────────
resource "aws_ecr_repository" "dr" {
  for_each             = local.ecr_names
  name                 = each.value
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
}

resource "aws_ecr_lifecycle_policy" "dr" {
  for_each   = aws_ecr_repository.dr
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Retain newest 10 images in DR (cost saving)"
      selection    = { tagStatus = "any"; countType = "imageCountMoreThan"; countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}

# ── S3 artifacts bucket in DR ─────────────────────────────────────────────────
resource "aws_s3_bucket" "dr" {
  bucket = "${var.project}-dr-${data.aws_caller_identity.current.account_id}-artifacts"
}
resource "aws_s3_bucket_versioning" "dr" {
  bucket = aws_s3_bucket.dr.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "dr" {
  bucket = aws_s3_bucket.dr.id
  rule { apply_server_side_encryption_by_default { sse_algorithm = "AES256" } }
}
resource "aws_s3_bucket_public_access_block" "dr" {
  bucket                  = aws_s3_bucket.dr.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Secrets Manager in DR region ──────────────────────────────────────────────
resource "aws_secretsmanager_secret" "jwt"       { name = "/${var.project}/dr/jwt-secret";       recovery_window_in_days = 7 }
resource "aws_secretsmanager_secret" "encryption" { name = "/${var.project}/dr/encryption-key";   recovery_window_in_days = 7 }
resource "aws_secretsmanager_secret" "database"   { name = "/${var.project}/dr/database";         recovery_window_in_days = 7 }
resource "aws_secretsmanager_secret" "upstox_id"  { name = "/${var.project}/dr/upstox-client-id"; recovery_window_in_days = 7 }
resource "aws_secretsmanager_secret" "upstox_sec" { name = "/${var.project}/dr/upstox-client-secret"; recovery_window_in_days = 7 }
resource "aws_secretsmanager_secret" "upstox_tok" { name = "/${var.project}/dr/upstox-access-token";  recovery_window_in_days = 7 }

resource "aws_secretsmanager_secret_version" "jwt"       { secret_id = aws_secretsmanager_secret.jwt.id;       secret_string = var.jwt_secret }
resource "aws_secretsmanager_secret_version" "encryption" { secret_id = aws_secretsmanager_secret.encryption.id; secret_string = var.encryption_key }
resource "aws_secretsmanager_secret_version" "database"   {
  secret_id     = aws_secretsmanager_secret.database.id
  secret_string = jsonencode({ username = var.timescale_db_user; password = var.db_password; database = var.timescale_db_name })
}
resource "aws_secretsmanager_secret_version" "upstox_id"  { secret_id = aws_secretsmanager_secret.upstox_id.id;  secret_string = var.upstox_client_id }
resource "aws_secretsmanager_secret_version" "upstox_sec" { secret_id = aws_secretsmanager_secret.upstox_sec.id; secret_string = var.upstox_client_secret }
resource "aws_secretsmanager_secret_version" "upstox_tok" { secret_id = aws_secretsmanager_secret.upstox_tok.id; secret_string = var.upstox_access_token }

# Connection-string secrets — these reference the DR TimescaleDB + Redis
resource "aws_secretsmanager_secret" "database_url"            { name = "/${var.project}/dr/database-url";            recovery_window_in_days = 7 }
resource "aws_secretsmanager_secret" "database_url_sync"       { name = "/${var.project}/dr/database-url-sync";       recovery_window_in_days = 7 }
resource "aws_secretsmanager_secret" "redis_url"               { name = "/${var.project}/dr/redis-url";               recovery_window_in_days = 7 }
resource "aws_secretsmanager_secret" "celery_broker_url"       { name = "/${var.project}/dr/celery-broker-url";       recovery_window_in_days = 7 }
resource "aws_secretsmanager_secret" "celery_result_backend"   { name = "/${var.project}/dr/celery-result-backend";   recovery_window_in_days = 7 }

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = "postgresql+asyncpg://${var.timescale_db_user}:${var.db_password}@${aws_instance.timescale.private_dns}:5432/${var.timescale_db_name}"
}
resource "aws_secretsmanager_secret_version" "database_url_sync" {
  secret_id     = aws_secretsmanager_secret.database_url_sync.id
  secret_string = "postgresql://${var.timescale_db_user}:${var.db_password}@${aws_instance.timescale.private_dns}:5432/${var.timescale_db_name}"
}
resource "aws_secretsmanager_secret_version" "redis_url" {
  secret_id     = aws_secretsmanager_secret.redis_url.id
  secret_string = "rediss://:${var.redis_auth_token}@${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379/0"
}
resource "aws_secretsmanager_secret_version" "celery_broker_url" {
  secret_id     = aws_secretsmanager_secret.celery_broker_url.id
  secret_string = "rediss://:${var.redis_auth_token}@${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379/2"
}
resource "aws_secretsmanager_secret_version" "celery_result_backend" {
  secret_id     = aws_secretsmanager_secret.celery_result_backend.id
  secret_string = "rediss://:${var.redis_auth_token}@${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379/2"
}

# ── IAM ───────────────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions    = ["sts:AssumeRole"]
    principals { type = "Service"; identifiers = ["ecs-tasks.amazonaws.com"] }
  }
}
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions    = ["sts:AssumeRole"]
    principals { type = "Service"; identifiers = ["ec2.amazonaws.com"] }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${var.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}
resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy" "ecs_secrets" {
  name = "${var.name}-read-secrets"
  role = aws_iam_role.ecs_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.jwt.arn,
        aws_secretsmanager_secret.encryption.arn,
        aws_secretsmanager_secret.database.arn,
        aws_secretsmanager_secret.upstox_id.arn,
        aws_secretsmanager_secret.upstox_sec.arn,
        aws_secretsmanager_secret.upstox_tok.arn,
        aws_secretsmanager_secret.database_url.arn,
        aws_secretsmanager_secret.database_url_sync.arn,
        aws_secretsmanager_secret.redis_url.arn,
        aws_secretsmanager_secret.celery_broker_url.arn,
        aws_secretsmanager_secret.celery_result_backend.arn,
      ]
    }]
  })
}

resource "aws_iam_role" "ecs_task" {
  name               = "${var.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}
resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "${var.name}-s3"
  role = aws_iam_role.ecs_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket"]
      Resource = [aws_s3_bucket.dr.arn, "${aws_s3_bucket.dr.arn}/*"]
    }]
  })
}

resource "aws_iam_role" "timescale" {
  name               = "${var.name}-timescale-ec2"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}
resource "aws_iam_role_policy_attachment" "timescale_ssm" {
  role       = aws_iam_role.timescale.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy" "timescale_secret" {
  name = "${var.name}-timescale-secret"
  role = aws_iam_role.timescale.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow"; Action = ["secretsmanager:GetSecretValue"]; Resource = [aws_secretsmanager_secret.database.arn] }]
  })
}
resource "aws_iam_instance_profile" "timescale" {
  name = "${var.name}-timescale-profile"
  role = aws_iam_role.timescale.name
}

# ── TimescaleDB DR — EC2 kept STOPPED in pilot-light ─────────────────────────
resource "aws_ebs_volume" "timescale" {
  availability_zone = var.data_subnet_ids[0] != "" ? data.aws_subnet.data_az.availability_zone : "ap-south-1a"
  size              = var.timescale_volume_size
  type              = "gp3"
  encrypted         = true
  iops              = 3000
  throughput        = 125
  tags              = { Name = "${var.name}-timescale-data" }
}

data "aws_subnet" "data_az" { id = var.data_subnet_ids[0] }

resource "aws_instance" "timescale" {
  ami                         = var.timescale_ami_id
  instance_type               = var.timescale_instance_type
  subnet_id                   = var.data_subnet_ids[0]
  vpc_security_group_ids      = [var.timescale_sg_id]
  iam_instance_profile        = aws_iam_instance_profile.timescale.name
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/user_data/timescale.sh.tftpl", {
    region         = var.dr_region
    secret_arn     = aws_secretsmanager_secret.database.arn
    db_name        = var.timescale_db_name
    db_user        = var.timescale_db_user
    image          = var.timescale_image
    data_device    = "/dev/sdf"
    data_volume_gb = var.timescale_volume_size
  })
  user_data_replace_on_change = false

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  tags = { Name = "${var.name}-timescale", DRRole = "standby" }

  lifecycle {
    # Keep the instance stopped after initial creation in pilot-light mode.
    # The failover Lambda will call ec2:StartInstances when region failover occurs.
    ignore_changes = [user_data]
  }
}

resource "aws_volume_attachment" "timescale" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.timescale.id
  instance_id = aws_instance.timescale.id
}

# Stop the instance after creation in pilot-light mode via local-exec
resource "null_resource" "stop_timescale_pilot_light" {
  count = var.dr_strategy == "pilot_light" ? 1 : 0
  triggers = { instance_id = aws_instance.timescale.id }
  provisioner "local-exec" {
    command = "aws ec2 stop-instances --instance-ids ${aws_instance.timescale.id} --region ${var.dr_region} || true"
  }
  depends_on = [aws_volume_attachment.timescale]
}

# ── Redis DR — cost-optimised single-node in pilot-light ─────────────────────
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.name}-redis-subnets"
  subnet_ids = var.data_subnet_ids
}
resource "aws_elasticache_parameter_group" "redis" {
  name   = "${var.name}-redis7"
  family = "redis7"
}
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "${var.project}-dr"
  description                = "StockMind DR Redis"
  engine                     = "redis"
  engine_version             = "7.1"
  # Pilot light: single node (cache.t4g.micro) — cheapest option
  # Warm standby: 2-node HA with auto-failover
  node_type                  = var.dr_strategy == "pilot_light" ? "cache.t4g.micro" : "cache.t4g.small"
  num_cache_clusters         = var.dr_strategy == "pilot_light" ? 1 : 2
  automatic_failover_enabled = var.dr_strategy != "pilot_light"
  multi_az_enabled           = var.dr_strategy != "pilot_light"
  parameter_group_name       = aws_elasticache_parameter_group.redis.name
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = [var.redis_sg_id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = var.redis_auth_token
  snapshot_retention_limit   = 3
  apply_immediately          = true
}

# ── TLS self-signed cert for DR ALB ──────────────────────────────────────────
resource "tls_private_key" "dr" {
  algorithm = "RSA"
  rsa_bits  = 2048
}
resource "tls_self_signed_cert" "dr" {
  private_key_pem       = tls_private_key.dr.private_key_pem
  validity_period_hours = 8760
  dns_names             = [var.domain_name, var.api_domain_name]
  subject               { common_name = var.domain_name; organization = "StockMind DR" }
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}
resource "aws_acm_certificate" "dr" {
  private_key      = tls_private_key.dr.private_key_pem
  certificate_body = tls_self_signed_cert.dr.cert_pem
}

# ── ALB ───────────────────────────────────────────────────────────────────────
resource "aws_lb" "dr" {
  name                       = "${var.name}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [var.alb_sg_id]
  subnets                    = var.public_subnet_ids
  enable_deletion_protection = false   # false in DR — easier to tear down
}

resource "aws_lb_target_group" "frontend" {
  name        = "${var.project}-dr-frontend"
  port        = 3000; protocol = "HTTP"; target_type = "ip"; vpc_id = var.vpc_id
  health_check { path = "/"; matcher = "200-399"; interval = 30; healthy_threshold = 2; unhealthy_threshold = 3 }
}
resource "aws_lb_target_group" "backend" {
  name        = "${var.project}-dr-backend"
  port        = 8000; protocol = "HTTP"; target_type = "ip"; vpc_id = var.vpc_id
  health_check { path = "/health"; matcher = "200"; interval = 30; healthy_threshold = 2; unhealthy_threshold = 3 }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.dr.arn; port = 80; protocol = "HTTP"
  default_action { type = "redirect"; redirect { port = "443"; protocol = "HTTPS"; status_code = "HTTP_301" } }
}
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.dr.arn; port = 443; protocol = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.dr.arn
  default_action    { type = "forward"; target_group_arn = aws_lb_target_group.frontend.arn }
}
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.https.arn; priority = 10
  action    { type = "forward"; target_group_arn = aws_lb_target_group.backend.arn }
  condition { host_header { values = [var.api_domain_name] } }
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────
resource "aws_ecs_cluster" "dr" {
  name = "${var.name}-cluster"
  setting { name = "containerInsights"; value = "enabled" }
}

resource "aws_cloudwatch_log_group" "app" {
  for_each          = toset(["frontend", "backend", "worker", "beat"])
  name              = "/ecs/${var.name}/${each.value}"
  retention_in_days = 7   # shorter retention in DR — cost saving
}

# ── ECS Task Definitions ──────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "frontend" {
  family                   = "${var.name}-frontend"
  requires_compatibilities = ["FARGATE"]; network_mode = "awsvpc"
  cpu                      = tostring(var.frontend_cpu); memory = tostring(var.frontend_memory)
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn
  container_definitions = jsonencode([{
    name         = "frontend"
    image        = "${aws_ecr_repository.dr["frontend"].repository_url}:${var.frontend_image_tag}"
    essential    = true
    portMappings = [{ containerPort = 3000; hostPort = 3000; protocol = "tcp" }]
    environment  = [
      { name = "NODE_ENV"; value = "production" },
      { name = "PORT"; value = "3000" },
      { name = "NEXT_PUBLIC_API_URL"; value = "https://${var.api_domain_name}" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options   = { "awslogs-group" = aws_cloudwatch_log_group.app["frontend"].name; "awslogs-region" = var.dr_region; "awslogs-stream-prefix" = "frontend" }
    }
  }])
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.name}-backend"
  requires_compatibilities = ["FARGATE"]; network_mode = "awsvpc"
  cpu                      = tostring(var.backend_cpu); memory = tostring(var.backend_memory)
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn
  container_definitions = jsonencode([{
    name         = "backend"
    image        = "${aws_ecr_repository.dr["backend"].repository_url}:${var.backend_image_tag}"
    essential    = true
    portMappings = [{ containerPort = 8000; hostPort = 8000; protocol = "tcp" }]
    environment  = [
      { name = "APP_ENV";             value = "production" },
      { name = "TZ";                  value = "Asia/Kolkata" },
      { name = "S3_BUCKET";           value = aws_s3_bucket.dr.bucket },
      { name = "FRONTEND_URL";        value = "https://${var.domain_name}" },
      { name = "CORS_ORIGINS";        value = "https://${var.domain_name}" },
      { name = "UPSTOX_REDIRECT_URI"; value = "https://${var.api_domain_name}/api/auth/callback" },
      { name = "KITE_REDIRECT_URI";   value = "https://${var.api_domain_name}/api/auth/kite/callback" }
    ]
    secrets = [
      { name = "DATABASE_URL";          valueFrom = aws_secretsmanager_secret.database_url.arn },
      { name = "DATABASE_URL_SYNC";     valueFrom = aws_secretsmanager_secret.database_url_sync.arn },
      { name = "REDIS_URL";             valueFrom = aws_secretsmanager_secret.redis_url.arn },
      { name = "CELERY_BROKER_URL";     valueFrom = aws_secretsmanager_secret.celery_broker_url.arn },
      { name = "CELERY_RESULT_BACKEND"; valueFrom = aws_secretsmanager_secret.celery_result_backend.arn },
      { name = "JWT_SECRET";            valueFrom = aws_secretsmanager_secret.jwt.arn },
      { name = "ENCRYPTION_KEY";        valueFrom = aws_secretsmanager_secret.encryption.arn },
      { name = "UPSTOX_CLIENT_ID";      valueFrom = aws_secretsmanager_secret.upstox_id.arn },
      { name = "UPSTOX_CLIENT_SECRET";  valueFrom = aws_secretsmanager_secret.upstox_sec.arn },
      { name = "UPSTOX_ACCESS_TOKEN";   valueFrom = aws_secretsmanager_secret.upstox_tok.arn }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options   = { "awslogs-group" = aws_cloudwatch_log_group.app["backend"].name; "awslogs-region" = var.dr_region; "awslogs-stream-prefix" = "backend" }
    }
  }])
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.name}-worker"
  requires_compatibilities = ["FARGATE"]; network_mode = "awsvpc"
  cpu                      = tostring(var.worker_cpu); memory = tostring(var.worker_memory)
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn
  container_definitions = jsonencode([{
    name      = "worker"
    image     = "${aws_ecr_repository.dr["backend"].repository_url}:${var.worker_image_tag}"
    essential = true
    command   = ["celery", "-A", "app.tasks.worker", "worker", "--loglevel=info"]
    environment = [{ name = "APP_ENV"; value = "production" }, { name = "TZ"; value = "Asia/Kolkata" }]
    secrets = [
      { name = "DATABASE_URL";          valueFrom = aws_secretsmanager_secret.database_url.arn },
      { name = "DATABASE_URL_SYNC";     valueFrom = aws_secretsmanager_secret.database_url_sync.arn },
      { name = "REDIS_URL";             valueFrom = aws_secretsmanager_secret.redis_url.arn },
      { name = "CELERY_BROKER_URL";     valueFrom = aws_secretsmanager_secret.celery_broker_url.arn },
      { name = "CELERY_RESULT_BACKEND"; valueFrom = aws_secretsmanager_secret.celery_result_backend.arn },
      { name = "JWT_SECRET";            valueFrom = aws_secretsmanager_secret.jwt.arn },
      { name = "ENCRYPTION_KEY";        valueFrom = aws_secretsmanager_secret.encryption.arn },
      { name = "UPSTOX_CLIENT_ID";      valueFrom = aws_secretsmanager_secret.upstox_id.arn },
      { name = "UPSTOX_CLIENT_SECRET";  valueFrom = aws_secretsmanager_secret.upstox_sec.arn },
      { name = "UPSTOX_ACCESS_TOKEN";   valueFrom = aws_secretsmanager_secret.upstox_tok.arn }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options   = { "awslogs-group" = aws_cloudwatch_log_group.app["worker"].name; "awslogs-region" = var.dr_region; "awslogs-stream-prefix" = "worker" }
    }
  }])
}

resource "aws_ecs_task_definition" "beat" {
  family                   = "${var.name}-beat"
  requires_compatibilities = ["FARGATE"]; network_mode = "awsvpc"
  cpu                      = tostring(var.beat_cpu); memory = tostring(var.beat_memory)
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn
  container_definitions = jsonencode([{
    name      = "beat"
    image     = "${aws_ecr_repository.dr["backend"].repository_url}:${var.beat_image_tag}"
    essential = true
    command   = ["celery", "-A", "app.tasks.worker", "beat", "--loglevel=info"]
    environment = [{ name = "APP_ENV"; value = "production" }, { name = "TZ"; value = "Asia/Kolkata" }]
    secrets = [
      { name = "DATABASE_URL";          valueFrom = aws_secretsmanager_secret.database_url.arn },
      { name = "DATABASE_URL_SYNC";     valueFrom = aws_secretsmanager_secret.database_url_sync.arn },
      { name = "REDIS_URL";             valueFrom = aws_secretsmanager_secret.redis_url.arn },
      { name = "CELERY_BROKER_URL";     valueFrom = aws_secretsmanager_secret.celery_broker_url.arn },
      { name = "CELERY_RESULT_BACKEND"; valueFrom = aws_secretsmanager_secret.celery_result_backend.arn },
      { name = "JWT_SECRET";            valueFrom = aws_secretsmanager_secret.jwt.arn },
      { name = "ENCRYPTION_KEY";        valueFrom = aws_secretsmanager_secret.encryption.arn }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options   = { "awslogs-group" = aws_cloudwatch_log_group.app["beat"].name; "awslogs-region" = var.dr_region; "awslogs-stream-prefix" = "beat" }
    }
  }])
}

# ── ECS Services — desired_count=0 in pilot-light; warm_standby_min_count in warm-standby ──
resource "aws_ecs_service" "frontend" {
  name            = "${var.name}-frontend-svc"
  cluster         = aws_ecs_cluster.dr.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = local.desired
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [var.frontend_sg_id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"; container_port = 3000
  }
  deployment_circuit_breaker { enable = true; rollback = true }
  lifecycle { ignore_changes = [desired_count] }  # Lambda manages scaling
  depends_on = [aws_lb_listener.https]
}

resource "aws_ecs_service" "backend" {
  name            = "${var.name}-backend-svc"
  cluster         = aws_ecs_cluster.dr.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = local.desired
  launch_type     = "FARGATE"
  health_check_grace_period_seconds = 120

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [var.backend_sg_id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"; container_port = 8000
  }
  deployment_circuit_breaker { enable = true; rollback = true }
  lifecycle { ignore_changes = [desired_count] }
  depends_on = [aws_lb_listener.https]
}

resource "aws_ecs_service" "worker" {
  name            = "${var.name}-worker-svc"
  cluster         = aws_ecs_cluster.dr.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = local.desired
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [var.worker_sg_id]
    assign_public_ip = false
  }
  deployment_circuit_breaker { enable = true; rollback = true }
  lifecycle { ignore_changes = [desired_count] }
}

resource "aws_ecs_service" "beat" {
  name            = "${var.name}-beat-svc"
  cluster         = aws_ecs_cluster.dr.id
  task_definition = aws_ecs_task_definition.beat.arn
  desired_count   = local.desired == 0 ? 0 : 1   # beat must be 0 or exactly 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [var.worker_sg_id]
    assign_public_ip = false
  }
  deployment_circuit_breaker { enable = true; rollback = true }
  lifecycle { ignore_changes = [desired_count] }
}

data "aws_caller_identity" "current" { provider = aws.primary }

# ── IAM role for S3 Cross-Region Replication ──────────────────────────────────
data "aws_iam_policy_document" "s3_crr_assume" {
  statement {
    actions    = ["sts:AssumeRole"]
    principals { type = "Service"; identifiers = ["s3.amazonaws.com"] }
  }
}
resource "aws_iam_role" "s3_crr" {
  provider           = aws.primary
  name               = "${var.name}-s3-crr-role"
  assume_role_policy = data.aws_iam_policy_document.s3_crr_assume.json
}
resource "aws_iam_role_policy" "s3_crr" {
  provider = aws.primary
  name     = "${var.name}-s3-crr-policy"
  role     = aws_iam_role.s3_crr.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        Resource = [var.primary_s3_bucket_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
        Resource = ["${var.primary_s3_bucket_arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
        Resource = ["${var.dr_s3_bucket_arn}/*"]
      }
    ]
  })
}

# ── S3 Cross-Region Replication ───────────────────────────────────────────────
resource "aws_s3_bucket_replication_configuration" "primary_to_dr" {
  provider = aws.primary
  bucket   = var.primary_s3_bucket_name
  role     = aws_iam_role.s3_crr.arn

  rule {
    id     = "replicate-all-to-dr"
    status = "Enabled"
    filter {}  # replicate all objects

    destination {
      bucket        = var.dr_s3_bucket_arn
      storage_class = "STANDARD_IA"   # cheaper in DR — read is rare until failover
    }
    delete_marker_replication { status = "Enabled" }
  }
}

# ── ECR Cross-Region Replication ──────────────────────────────────────────────
# ECR replication is account-level and must be configured once per account.
# This pushes images from primary (ap-south-2) → DR (ap-south-1) automatically on push.
resource "aws_ecr_replication_configuration" "cross_region" {
  provider = aws.primary
  replication_configuration {
    rule {
      destination {
        region      = var.dr_region
        registry_id = data.aws_caller_identity.current.account_id
      }
      repository_filter {
        filter      = var.project
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

# ── AWS Backup — cross-region copy of EBS snapshots ──────────────────────────
resource "aws_backup_vault" "primary" {
  provider = aws.primary
  name     = "${var.name}-primary-vault"
}
resource "aws_backup_vault" "dr" {
  provider = aws.dr
  name     = "${var.name}-dr-vault"
}

data "aws_iam_policy_document" "backup_assume" {
  statement {
    actions    = ["sts:AssumeRole"]
    principals { type = "Service"; identifiers = ["backup.amazonaws.com"] }
  }
}
resource "aws_iam_role" "backup" {
  provider           = aws.primary
  name               = "${var.name}-backup-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
}
resource "aws_iam_role_policy_attachment" "backup" {
  provider   = aws.primary
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}
resource "aws_iam_role_policy_attachment" "backup_restore" {
  provider   = aws.primary
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_backup_plan" "timescale_crr" {
  provider = aws.primary
  name     = "${var.name}-timescale-crr"

  rule {
    rule_name         = "daily-with-dr-copy"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 2 * * ? *)"   # 02:00 UTC daily (~7:30 IST)
    lifecycle         { delete_after = 30 }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn
      lifecycle             { delete_after = 14 }   # keep 14 days in DR — cost saving
    }
  }
}

resource "aws_backup_selection" "timescale" {
  provider     = aws.primary
  name         = "${var.name}-timescale-ebs"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.timescale_crr.id
  resources    = ["arn:aws:ec2:${var.primary_region}:${data.aws_caller_identity.current.account_id}:instance/*"]
  condition {
    string_equals {
      key   = "aws:ResourceTag/DRRole"
      value = "primary"
    }
  }
}

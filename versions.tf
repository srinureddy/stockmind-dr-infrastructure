terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Primary region — existing StockMind production stack
provider "aws" {
  alias  = "primary"
  region = var.primary_region
  default_tags {
    tags = {
      Application = "StockMind"
      ManagedBy   = "Terraform"
      Role        = "Primary"
      Environment = var.environment
    }
  }
}

# DR region — pilot-light standby
provider "aws" {
  alias  = "dr"
  region = var.dr_region
  default_tags {
    tags = {
      Application = "StockMind"
      ManagedBy   = "Terraform"
      Role        = "DR"
      Environment = var.environment
    }
  }
}

# us-east-1 is required for Route 53 health-check alarms
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      Application = "StockMind"
      ManagedBy   = "Terraform"
      Role        = "Global"
      Environment = var.environment
    }
  }
}

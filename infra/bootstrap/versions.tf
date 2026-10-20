terraform {
  # 1.10 introduced S3-native state locking (use_lockfile), which the live
  # stacks rely on instead of a DynamoDB table.
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  # Intentionally local state: this stack creates the remote backend, so it
  # cannot also live in it. See README.md.
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project   = "cloud-platform-blueprint"
      ManagedBy = "terraform"
      Owner     = "platform-team"
      Component = "tfstate-bootstrap"
    }
  }
}

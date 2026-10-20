# Root configuration for every AWS unit under infra/live/aws.
#
# Each unit includes this file, so the backend, provider and version
# constraints are defined exactly once. Functions such as
# find_in_parent_folders() are evaluated from the including unit's directory,
# which is how one file resolves a different env.hcl for dev and prod.
#
# The Azure stack does not include this file because its state lives in Azure
# Storage, not S3. See infra/live/azure/dev/aks/terragrunt.hcl.

locals {
  common = read_terragrunt_config("${get_parent_terragrunt_dir()}/common.hcl").locals
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals

  default_tags = {
    Project     = local.common.project
    Environment = local.env.environment
    ManagedBy   = "terraform"
    Owner       = local.common.owner
  }
}

# use_lockfile needs Terraform 1.10+.
terraform_version_constraint  = ">= 1.10.0"
terragrunt_version_constraint = ">= 1.0.0"

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    # Created by infra/bootstrap, which uses the same naming scheme.
    bucket = "cpb-tfstate-${local.env.account_id}-${local.env.region}"
    # Forward slashes even on Windows, or the same stack gets a different key per OS.
    key     = "${replace(path_relative_to_include(), "\\", "/")}/terraform.tfstate"
    region  = local.env.region
    encrypt = true
    # S3-native locking: a conditional write of <key>.tflock replaces DynamoDB.
    use_lockfile = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.env.region}"

      # Refuse to run if the credentials belong to a different account, so a
      # dev profile can never apply to prod (or the reverse).
      allowed_account_ids = ["${local.env.account_id}"]

      default_tags {
        tags = ${jsonencode(local.default_tags)}
      }
    }
  EOF
}

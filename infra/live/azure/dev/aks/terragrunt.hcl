# Azure dev AKS.
#
# This unit does not include root.hcl: that file configures an S3 backend and
# the AWS provider. Azure state lives in a Storage account, so the backend and
# provider are generated here instead, with the same tag set.

locals {
  common = read_terragrunt_config(find_in_parent_folders("common.hcl")).locals
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals

  tags = {
    Project     = local.common.project
    Environment = local.env.environment
    ManagedBy   = "terraform"
    Owner       = local.common.owner
  }
}

terraform_version_constraint  = ">= 1.10.0"
terragrunt_version_constraint = ">= 1.0.0"

terraform {
  source = "${get_repo_root()}/infra/modules//azure-aks"
}

# The azurerm backend locks with blob leases, so it needs no extra lock store.
# use_azuread_auth authenticates with Entra ID rather than storage account keys.
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      backend "azurerm" {
        resource_group_name  = "${local.env.state_resource_group}"
        storage_account_name = "${local.env.state_storage_account}"
        container_name       = "tfstate"
        key                  = "${trimprefix(replace(get_path_from_repo_root(), "\\", "/"), "infra/live/")}/terraform.tfstate"
        use_azuread_auth     = true
      }
    }
  EOF
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "azurerm" {
      features {}
      subscription_id     = "${local.env.subscription_id}"
      storage_use_azuread = true
    }
  EOF
}

inputs = {
  name                            = "cpb-${local.env.environment}"
  location                        = local.env.location
  kubernetes_version              = local.env.kubernetes_version
  sku_tier                        = local.env.sku_tier
  vnet_cidr                       = local.env.vnet_cidr
  node_subnet_cidr                = local.env.node_subnet_cidr
  api_server_authorized_ip_ranges = local.env.api_server_authorized_ip_ranges
  admin_group_object_ids          = local.env.admin_group_object_ids
  log_retention_days              = local.env.log_retention_days
  # azurerm has no provider-level default tags, so they are passed explicitly.
  tags = local.tags
}

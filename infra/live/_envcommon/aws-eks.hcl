# EKS settings shared by every AWS environment.

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//aws-eks"
}

# Relative to the including unit, so this resolves to <env>/vpc.
dependency "vpc" {
  config_path = "../vpc"

  # Lets `init`, `validate` and `plan` run before the VPC has been applied
  # (e.g. a first `terragrunt run --all plan` on a fresh account). Never used
  # for apply: Terragrunt refuses and asks for the real outputs.
  mock_outputs = {
    vpc_id             = "vpc-00000000000000000"
    private_subnet_ids = ["subnet-00000000000000001", "subnet-00000000000000002", "subnet-00000000000000003"]
    intra_subnet_ids   = ["subnet-00000000000000004", "subnet-00000000000000005", "subnet-00000000000000006"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  cluster_name             = "cpb-${local.env.environment}"
  kubernetes_version       = local.env.kubernetes_version
  vpc_id                   = dependency.vpc.outputs.vpc_id
  private_subnet_ids       = dependency.vpc.outputs.private_subnet_ids
  control_plane_subnet_ids = dependency.vpc.outputs.intra_subnet_ids
  endpoint_public_access   = local.env.endpoint_public_access
  public_access_cidrs      = local.env.public_access_cidrs
  system_node_count        = local.env.system_node_count
  admin_role_arns          = local.env.admin_role_arns
  log_retention_days       = local.env.log_retention_days
}

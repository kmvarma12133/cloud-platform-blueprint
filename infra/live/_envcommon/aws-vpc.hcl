# VPC settings shared by every AWS environment. Units include this file and
# only override what is genuinely environment-specific (all of which comes from
# env.hcl today).

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//aws-vpc"
}

inputs = {
  name                    = "cpb-${local.env.environment}"
  cluster_name            = "cpb-${local.env.environment}"
  cidr_block              = local.env.vpc_cidr
  azs                     = local.env.azs
  single_nat_gateway      = local.env.single_nat_gateway
  flow_log_retention_days = local.env.log_retention_days
}

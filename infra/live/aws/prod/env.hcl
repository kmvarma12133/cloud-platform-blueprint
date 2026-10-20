# Everything that differs between dev and prod lives here.
# Replace account_id and admin_role_arns with your own before running.

locals {
  environment = "prod"
  account_id  = "222222222222"
  region      = "eu-west-1"
  azs         = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  vpc_cidr = "10.20.0.0/16"

  # One NAT gateway per AZ: an AZ outage must not take down egress for the others.
  single_nat_gateway = false

  kubernetes_version = "1.35"
  system_node_count  = 3

  # Private endpoint only; operators reach the API through SSM or the VPN.
  endpoint_public_access = false
  public_access_cidrs    = []

  admin_role_arns = ["arn:aws:iam::222222222222:role/platform-admin"]

  log_retention_days = 365
}

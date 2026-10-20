# Everything that differs between dev and prod lives here.
# Replace account_id and admin_role_arns with your own before running.

locals {
  environment = "dev"
  account_id  = "111111111111"
  region      = "eu-west-1"
  azs         = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  # Non-overlapping ranges per environment (and Azure) so VPCs can be peered later.
  vpc_cidr = "10.10.0.0/16"

  # One NAT gateway instead of three saves ~$70/month in hourly charges; if its AZ
  # fails, dev loses egress, which is acceptable.
  single_nat_gateway = true

  kubernetes_version = "1.35"
  system_node_count  = 2

  # Public API endpoint for convenience in dev, restricted to an allowlist.
  # 203.0.113.0/24 is a documentation range: replace it with your VPN/office egress.
  endpoint_public_access = true
  public_access_cidrs    = ["203.0.113.0/24"]

  admin_role_arns = ["arn:aws:iam::111111111111:role/platform-admin"]

  log_retention_days = 30
}

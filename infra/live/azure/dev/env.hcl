# Azure dev environment. Replace the IDs with your own before running.

locals {
  environment     = "dev"
  subscription_id = "00000000-0000-0000-0000-000000000000"
  location        = "westeurope"

  # Created once with the az CLI; see infra/bootstrap/README.md.
  state_resource_group  = "rg-cpb-tfstate"
  state_storage_account = "cpbtfstatedev"

  kubernetes_version = "1.35"

  # Free tier has no uptime SLA, which is fine for dev.
  sku_tier = "Free"

  # Distinct from the AWS VPCs (10.10/16, 10.20/16) so the clouds can be connected later.
  vnet_cidr        = "10.30.0.0/16"
  node_subnet_cidr = "10.30.0.0/22"

  # Documentation range: replace with your VPN/office egress.
  api_server_authorized_ip_ranges = ["203.0.113.0/24"]
  admin_group_object_ids          = ["00000000-0000-0000-0000-000000000000"]

  log_retention_days = 30
}

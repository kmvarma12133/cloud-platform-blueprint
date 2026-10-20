resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name}"
  location = var.location
  tags     = var.tags
}

# --- Network -----------------------------------------------------------------
# With Azure CNI Overlay only node NICs take VNet addresses; pods get IPs from
# pod_cidr, so a /22 node subnet is plenty and the VNet stays easy to peer.

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "snet-${var.name}-nodes"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.node_subnet_cidr]
}

# Default rules only (VNet and load balancer traffic in, nothing from the
# internet). AKS adds its own rules for Services of type LoadBalancer.
resource "azurerm_network_security_group" "nodes" {
  name                = "nsg-${var.name}-nodes"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "nodes" {
  subnet_id                 = azurerm_subnet.nodes.id
  network_security_group_id = azurerm_network_security_group.nodes.id
}

# --- Identity ----------------------------------------------------------------
# A user-assigned control-plane identity can be granted rights on the subnet
# before the cluster exists, which a system-assigned one cannot.

resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "id-${var.name}-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

# Needed so AKS can attach internal load balancers and NICs to our subnet.
resource "azurerm_role_assignment" "control_plane_network" {
  scope                = azurerm_subnet.nodes.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
}

# --- Monitoring --------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

# --- Cluster -----------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "this" {
  #checkov:skip=CKV_AZURE_6:Ranges come from a required variable whose validation rejects an empty list and 0.0.0.0/0; checkov cannot resolve it statically.
  #checkov:skip=CKV_AZURE_115:Public API restricted by authorized IP ranges; a private cluster needs a VPN or Bastion path that is out of scope for this reference.
  #checkov:skip=CKV_AZURE_117:Platform-managed keys are used; a customer-managed disk encryption set adds a Key Vault dependency this reference does not need.

  name                = var.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  node_resource_group = "rg-${var.name}-nodes"
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  # Identity: Entra ID users and groups only, no static kubeconfig credentials.
  local_account_disabled            = true
  role_based_access_control_enabled = true
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  # Workload identity: pods federate their service account token with an
  # Entra ID app or managed identity instead of mounting secrets.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  api_server_access_profile {
    authorized_ip_ranges = var.api_server_authorized_ip_ranges
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_vm_size
    vnet_subnet_id               = azurerm_subnet.nodes.id
    zones                        = ["1", "2", "3"]
    only_critical_addons_enabled = true
    auto_scaling_enabled         = true
    min_count                    = var.system_node_count
    max_count                    = var.system_node_count + 2
    max_pods                     = 110
    os_sku                       = "AzureLinux"
    # Ephemeral OS disk lives on the VM's local SSD: faster and no managed-disk cost.
    os_disk_type                = "Ephemeral"
    os_disk_size_gb             = 128
    host_encryption_enabled     = true
    temporary_name_for_rotation = "systemtmp"
    tags                        = var.tags

    upgrade_settings {
      max_surge = "33%"
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  azure_policy_enabled = true

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  # Container Insights, authenticating with the cluster's managed identity.
  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.this.id
    msi_auth_for_monitoring_enabled = true
  }

  tags = var.tags

  depends_on = [azurerm_role_assignment.control_plane_network]

  lifecycle {
    # The autoscaler owns node counts after creation.
    ignore_changes = [default_node_pool[0].node_count]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                    = "user"
  kubernetes_cluster_id   = azurerm_kubernetes_cluster.this.id
  mode                    = "User"
  vm_size                 = var.user_vm_size
  vnet_subnet_id          = azurerm_subnet.nodes.id
  zones                   = ["1", "2", "3"]
  auto_scaling_enabled    = true
  min_count               = var.user_min_count
  max_count               = var.user_max_count
  max_pods                = 110
  os_sku                  = "AzureLinux"
  os_disk_type            = "Ephemeral"
  os_disk_size_gb         = 128
  host_encryption_enabled = true
  tags                    = var.tags

  upgrade_settings {
    max_surge = "33%"
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

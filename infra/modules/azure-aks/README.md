# azure-aks

An AKS cluster in its own resource group, VNet and subnet, as the Azure
counterpart to `aws-vpc` plus `aws-eks`.

What's in it:

- **Networking: Azure CNI Overlay with the Cilium dataplane.** Only nodes use
  VNet addresses; pods get IPs from `pod_cidr`. That keeps the subnet small
  and the VNet easy to peer. Cilium enforces NetworkPolicy in eBPF.
- **Node pools:**
  - A **system** pool spread across zones 1–3 with
    `only_critical_addons_enabled`, so application pods never land on it.
  - An autoscaled **user** pool for applications.
  - Both use Azure Linux, ephemeral OS disks and host encryption.
- **Identity:**
  - Entra ID with Azure RBAC, and **local accounts disabled**, so no static
    admin kubeconfig exists.
  - A user-assigned control-plane identity, granted Network Contributor on
    the subnet before the cluster is created.
  - Workload identity and the OIDC issuer are enabled for pod-level
    federation.
- **Add-ons:**
  - The Azure Policy add-on, which runs Gatekeeper under the hood.
  - The Key Vault Secrets Store CSI driver, with rotation.
  - Container Insights, sending to a dedicated Log Analytics workspace with
    managed-identity auth.
- **Upgrades:** the `patch` channel for Kubernetes and the `NodeImage` channel
  for node OS images.

`api_server_authorized_ip_ranges` is required, and validation rejects an empty
list or `0.0.0.0/0`. The alternative is a private cluster. This module doesn't
build one because that needs a network path in (VPN or Bastion), which is out
of scope here.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.6.0 |
| azurerm | ~> 4.81 |

## Providers

| Name | Version |
| ---- | ------- |
| azurerm | ~> 4.81 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_kubernetes_cluster.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster) | resource |
| [azurerm_kubernetes_cluster_node_pool.user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_node_pool) | resource |
| [azurerm_log_analytics_workspace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace) | resource |
| [azurerm_network_security_group.nodes](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_role_assignment.control_plane_network](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_subnet.nodes](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_network_security_group_association.nodes](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_user_assigned_identity.control_plane](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_virtual_network.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| api_server_authorized_ip_ranges | CIDRs allowed to reach the API server (office or VPN egress, CI runners). Required: an empty list would leave the API open to the internet. | `list(string)` | n/a | yes |
| location | Azure region. | `string` | n/a | yes |
| name | Name prefix for all resources (e.g. platform-dev). Also used as the cluster name. | `string` | n/a | yes |
| admin_group_object_ids | Entra ID group object IDs granted cluster-admin through Azure RBAC. | `list(string)` | `[]` | no |
| dns_service_ip | CoreDNS ClusterIP. Must sit inside service_cidr. | `string` | `"172.16.0.10"` | no |
| kubernetes_version | Kubernetes minor version. Patch upgrades are applied automatically by the upgrade channel. | `string` | `"1.35"` | no |
| log_retention_days | Log Analytics retention for Container Insights. | `number` | `30` | no |
| node_subnet_cidr | Subnet for node NICs. Must sit inside vnet_cidr. | `string` | `"10.30.0.0/22"` | no |
| pod_cidr | Overlay CIDR for pod IPs. Must not overlap the VNet or anything it peers with. | `string` | `"192.168.0.0/16"` | no |
| service_cidr | ClusterIP service range. Must not overlap the VNet or pod_cidr. | `string` | `"172.16.0.0/16"` | no |
| sku_tier | AKS control-plane tier. Standard adds the uptime SLA; dev can override to Free. | `string` | `"Standard"` | no |
| system_node_count | Minimum nodes in the system pool. Three gives one per zone. | `number` | `3` | no |
| system_vm_size | VM size for the system pool (CoreDNS, metrics-server, Azure add-ons only). | `string` | `"Standard_D4ds_v5"` | no |
| tags | Tags applied to every resource. | `map(string)` | `{}` | no |
| user_max_count | Cluster autoscaler ceiling for the user pool. | `number` | `10` | no |
| user_min_count | Cluster autoscaler floor for the user pool. | `number` | `2` | no |
| user_vm_size | VM size for the user (application) pool. | `string` | `"Standard_D4ds_v5"` | no |
| vnet_cidr | Address space of the cluster VNet. Only nodes consume VNet IPs (pods use the overlay CIDR). | `string` | `"10.30.0.0/16"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cluster_id | AKS cluster resource ID (scope for Azure RBAC role assignments). |
| cluster_name | AKS cluster name. |
| key_vault_secrets_provider_identity_client_id | Client ID of the Key Vault CSI driver identity. |
| kubelet_identity_object_id | Kubelet managed identity object ID (grant AcrPull on the registry). |
| log_analytics_workspace_id | Log Analytics workspace used by Container Insights. |
| oidc_issuer_url | OIDC issuer URL for workload identity federated credentials. |
| resource_group_name | Resource group holding the cluster, VNet and workspace. |
| vnet_id | Cluster VNet ID (for peering). |
<!-- END_TF_DOCS -->

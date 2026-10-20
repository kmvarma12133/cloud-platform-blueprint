output "cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_id" {
  description = "AKS cluster resource ID (scope for Azure RBAC role assignments)."
  value       = azurerm_kubernetes_cluster.this.id
}

output "resource_group_name" {
  description = "Resource group holding the cluster, VNet and workspace."
  value       = azurerm_resource_group.this.name
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity federated credentials."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  description = "Kubelet managed identity object ID (grant AcrPull on the registry)."
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

output "key_vault_secrets_provider_identity_client_id" {
  description = "Client ID of the Key Vault CSI driver identity."
  value       = azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0].client_id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace used by Container Insights."
  value       = azurerm_log_analytics_workspace.this.id
}

output "vnet_id" {
  description = "Cluster VNet ID (for peering)."
  value       = azurerm_virtual_network.this.id
}

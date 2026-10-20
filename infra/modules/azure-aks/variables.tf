variable "name" {
  description = "Name prefix for all resources (e.g. platform-dev). Also used as the cluster name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version. Patch upgrades are applied automatically by the upgrade channel."
  type        = string
  default     = "1.35"
}

variable "sku_tier" {
  description = "AKS control-plane tier. Standard adds the uptime SLA; dev can override to Free."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}

variable "vnet_cidr" {
  description = "Address space of the cluster VNet. Only nodes consume VNet IPs (pods use the overlay CIDR)."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.vnet_cidr, 0))
    error_message = "vnet_cidr must be a valid IPv4 CIDR."
  }
}

variable "node_subnet_cidr" {
  description = "Subnet for node NICs. Must sit inside vnet_cidr."
  type        = string
  default     = "10.20.0.0/22"
}

variable "pod_cidr" {
  description = "Overlay CIDR for pod IPs. Must not overlap the VNet or anything it peers with."
  type        = string
  default     = "192.168.0.0/16"
}

variable "service_cidr" {
  description = "ClusterIP service range. Must not overlap the VNet or pod_cidr."
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "CoreDNS ClusterIP. Must sit inside service_cidr."
  type        = string
  default     = "172.16.0.10"
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the API server (office or VPN egress, CI runners). Required: an empty list would leave the API open to the internet."
  type        = list(string)

  validation {
    condition     = length(var.api_server_authorized_ip_ranges) > 0 && alltrue([for c in var.api_server_authorized_ip_ranges : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "Provide at least one valid CIDR, and not 0.0.0.0/0."
  }
}

variable "admin_group_object_ids" {
  description = "Entra ID group object IDs granted cluster-admin through Azure RBAC."
  type        = list(string)
  default     = []
}

variable "system_vm_size" {
  description = "VM size for the system pool (CoreDNS, metrics-server, Azure add-ons only)."
  type        = string
  default     = "Standard_D4ds_v5"
}

variable "system_node_count" {
  description = "Minimum nodes in the system pool. Three gives one per zone."
  type        = number
  default     = 3
}

variable "user_vm_size" {
  description = "VM size for the user (application) pool."
  type        = string
  default     = "Standard_D4ds_v5"
}

variable "user_min_count" {
  description = "Cluster autoscaler floor for the user pool."
  type        = number
  default     = 2
}

variable "user_max_count" {
  description = "Cluster autoscaler ceiling for the user pool."
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "Log Analytics retention for Container Insights."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version."
  type        = string
  default     = "1.31"
}

variable "vpc_id" {
  description = "VPC the cluster runs in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets for worker nodes."
  type        = list(string)
}

variable "control_plane_subnet_ids" {
  description = "Subnets for control-plane ENIs (intra subnets)."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Expose the API server publicly. Keep false in prod and reach it over VPN/SSM."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to the public endpoint when it is enabled."
  type        = list(string)
  default     = []
}

variable "system_node_instance_types" {
  description = "Instance types for the small managed node group that runs cluster-critical add-ons (Karpenter, CoreDNS). App workloads are scheduled by Karpenter."
  type        = list(string)
  default     = ["m6i.large"]
}

variable "system_node_count" {
  description = "Desired/min size of the system node group."
  type        = number
  default     = 2
}

variable "admin_role_arns" {
  description = "IAM role ARNs granted cluster-admin through EKS access entries (e.g. the platform team SSO role)."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Retention for control-plane logs."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

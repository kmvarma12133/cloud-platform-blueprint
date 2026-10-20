variable "name" {
  description = "Name prefix for all resources (e.g. platform-dev)."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR. A /16 leaves room for 3 AZs x (public + private + intra) /20s."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count must be between 2 and 4."
  }
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all AZs. Cheaper for dev; set false in prod for AZ-level resilience."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name, used for subnet discovery tags (load balancers, Karpenter)."
  type        = string
}

variable "flow_log_retention_days" {
  description = "CloudWatch retention for VPC flow logs."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

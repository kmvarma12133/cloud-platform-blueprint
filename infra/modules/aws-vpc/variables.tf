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

variable "azs" {
  description = "Availability zone names to spread subnets across, e.g. [\"eu-west-1a\", \"eu-west-1b\", \"eu-west-1c\"]."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 4
    error_message = "azs must list between 2 and 4 zones."
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
  description = "CloudWatch retention for VPC flow logs. Defaults to a year for audit; dev overrides it lower to save cost."
  type        = number
  default     = 365
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

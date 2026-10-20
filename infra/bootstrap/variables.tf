variable "account_id" {
  description = "AWS account that will hold the state bucket. The provider refuses to run against any other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  description = "Region for the state bucket. Must match the region in infra/live/aws/<env>/env.hcl."
  type        = string
}

variable "noncurrent_version_retention_days" {
  description = "How long superseded state versions are kept for rollback."
  type        = number
  default     = 90
}

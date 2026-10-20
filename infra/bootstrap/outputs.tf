output "state_bucket" {
  description = "Name of the remote state bucket used by infra/live/root.hcl."
  value       = aws_s3_bucket.state.id
}

output "state_kms_key_arn" {
  description = "CMK that encrypts state objects."
  value       = aws_kms_key.state.arn
}

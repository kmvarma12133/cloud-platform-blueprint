output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (worker nodes and pods)."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (internet-facing load balancers)."
  value       = aws_subnet.public[*].id
}

output "intra_subnet_ids" {
  description = "Intra subnet IDs (EKS control-plane ENIs)."
  value       = aws_subnet.intra[*].id
}

output "azs" {
  description = "Availability zones in use."
  value       = local.azs
}

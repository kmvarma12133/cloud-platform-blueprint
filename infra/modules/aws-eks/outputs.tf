output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority" {
  description = "Base64 CA bundle for the API server."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA trust policies."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "karpenter_node_role_name" {
  description = "Role name referenced by the Karpenter EC2NodeClass."
  value       = aws_iam_role.karpenter_node.name
}

output "karpenter_interruption_queue" {
  description = "SQS queue name passed to the Karpenter Helm chart."
  value       = aws_sqs_queue.karpenter_interruption.name
}

output "external_secrets_role_arn" {
  description = "Role assumed by the External Secrets Operator through Pod Identity."
  value       = aws_iam_role.external_secrets.arn
}

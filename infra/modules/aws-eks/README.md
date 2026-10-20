# aws-eks

An EKS cluster plus the AWS-side pieces Karpenter needs. Karpenter itself, and
every other in-cluster component, is installed by Argo CD from
`platform/gitops`.

What's in it:

- **Control plane.** API endpoint is private by default. Control-plane ENIs sit
  in the intra subnets. All five control-plane log types go to CloudWatch.
- **Encryption.** One rotating CMK encrypts Kubernetes Secrets and the
  control-plane log group. The cluster role gets an explicit KMS policy,
  because `AmazonEKSClusterPolicy` has none.
- **Access.** `authentication_mode = "API"` with access entries; there is no
  `aws-auth` ConfigMap to drift. The cluster creator gets no implicit admin;
  admins are listed in `admin_role_arns`.
- **System node group.** A small on-demand Bottlerocket group, tainted
  `CriticalAddonsOnly`, for CoreDNS, Karpenter and other add-ons. Application
  pods land on Karpenter-provisioned nodes.
- **Managed add-ons.** VPC CNI, CoreDNS, kube-proxy, the Pod Identity agent
  and the EBS CSI driver. The EBS CSI driver uses IRSA because that add-on
  configures its identity through `service_account_role_arn`.
- **Karpenter (`karpenter.tf`):**
  - A node role with an access entry of type `EC2_LINUX`.
  - A controller role bound through EKS Pod Identity.
  - A controller policy scoped by resource ARN and ownership tags, following
    the upstream reference policy.
  - An SQS queue fed by EventBridge for spot interruption, rebalance,
    state-change and health events.

See [ADR 0005](../../../docs/adr/0005-eks-pod-identity-vs-irsa.md) for when
this repo uses Pod Identity and when it uses IRSA.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.6.0 |
| aws | ~> 5.70 |
| tls | ~> 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | ~> 5.70 |
| tls | ~> 4.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_event_rule.karpenter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.karpenter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_log_group.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_eks_access_entry.admins](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_eks_access_entry.karpenter_node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_eks_access_policy_association.admins](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_policy_association) | resource |
| [aws_eks_addon.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster) | resource |
| [aws_eks_node_group.system](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group) | resource |
| [aws_eks_pod_identity_association.karpenter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_openid_connect_provider.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.karpenter_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.karpenter_node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.cluster_encryption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.karpenter_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.karpenter_node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.eks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.eks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_security_group.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_sqs_queue.karpenter_interruption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue_policy.karpenter_interruption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.cluster_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.cluster_encryption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ebs_csi_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.eks_kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.karpenter_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.karpenter_controller_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.karpenter_queue](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.node_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [tls_certificate.oidc](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/data-sources/certificate) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cluster_name | EKS cluster name. | `string` | n/a | yes |
| control_plane_subnet_ids | Subnets for control-plane ENIs (intra subnets). | `list(string)` | n/a | yes |
| private_subnet_ids | Subnets for worker nodes. | `list(string)` | n/a | yes |
| vpc_id | VPC the cluster runs in. | `string` | n/a | yes |
| admin_role_arns | IAM role ARNs granted cluster-admin through EKS access entries (e.g. the platform team SSO role). | `list(string)` | `[]` | no |
| endpoint_public_access | Expose the API server publicly. Keep false in prod and reach it over VPN/SSM. | `bool` | `false` | no |
| kubernetes_version | Kubernetes minor version. | `string` | `"1.35"` | no |
| log_retention_days | Retention for control-plane logs. Defaults to a year for audit; dev overrides it lower to save cost. | `number` | `365` | no |
| public_access_cidrs | CIDRs allowed to the public endpoint when it is enabled. | `list(string)` | `[]` | no |
| system_node_count | Desired/min size of the system node group. | `number` | `2` | no |
| system_node_instance_types | Instance types for the small managed node group that runs cluster-critical add-ons (Karpenter, CoreDNS). App workloads are scheduled by Karpenter. | `list(string)` | ```[ "m6i.large" ]``` | no |
| tags | Tags applied to every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cluster_certificate_authority | Base64 CA bundle for the API server. |
| cluster_endpoint | API server endpoint. |
| cluster_name | EKS cluster name. |
| karpenter_interruption_queue | SQS queue name passed to the Karpenter Helm chart. |
| karpenter_node_role_name | Role name referenced by the Karpenter EC2NodeClass. |
| oidc_provider_arn | OIDC provider ARN for IRSA trust policies. |
<!-- END_TF_DOCS -->

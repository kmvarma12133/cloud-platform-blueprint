# aws-vpc

A VPC laid out for EKS across 2–4 named availability zones.

| Tier | Size per AZ | Purpose | Internet |
|---|---|---|---|
| public | /20 | Internet-facing load balancers, NAT gateways | In and out via the IGW |
| private | /20 | Nodes and pods (VPC CNI gives pods VPC IPs) | Out only, via NAT |
| intra | /20 | EKS control-plane ENIs | None |

The subnets are carved with `cidrsubnet(cidr, 4, n)`: public uses indexes 0–3,
private 4–7 and intra 8–11, which leaves 12–15 of a /16 free for later.

Design choices:

- **Zones are pinned by name.** Selecting "the first N" would let a new AZ
  reorder the list and force subnets to be rebuilt.
- **NAT topology is an input.** One gateway in dev saves money. One per AZ in
  prod means an AZ outage doesn't cut egress for the others.
- **S3 gateway endpoint.** Image layers and other S3 traffic bypass NAT data
  processing charges.
- **Locked-down default security group**, so nothing can use it by accident.
- **Flow logs to CloudWatch**, encrypted with a dedicated CMK.
- **Discovery tags.** Subnets are tagged for the AWS Load Balancer Controller
  (`kubernetes.io/role/*elb`) and for Karpenter (`karpenter.sh/discovery`).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.6.0 |
| aws | ~> 5.70 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | ~> 5.70 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_default_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_kms_key.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route.private_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_subnet.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_availability_zones.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.flow_logs_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.flow_logs_kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| azs | Availability zone names to spread subnets across, e.g. ["eu-west-1a", "eu-west-1b", "eu-west-1c"]. | `list(string)` | n/a | yes |
| cluster_name | EKS cluster name, used for subnet discovery tags (load balancers, Karpenter). | `string` | n/a | yes |
| name | Name prefix for all resources (e.g. platform-dev). | `string` | n/a | yes |
| cidr_block | VPC CIDR. A /16 leaves room for 3 AZs x (public + private + intra) /20s. | `string` | `"10.0.0.0/16"` | no |
| flow_log_retention_days | CloudWatch retention for VPC flow logs. Defaults to a year for audit; dev overrides it lower to save cost. | `number` | `365` | no |
| single_nat_gateway | Use one NAT gateway for all AZs. Cheaper for dev; set false in prod for AZ-level resilience. | `bool` | `true` | no |
| tags | Tags applied to every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| azs | Availability zones in use. |
| intra_subnet_ids | Intra subnet IDs (EKS control-plane ENIs). |
| private_subnet_ids | Private subnet IDs (worker nodes and pods). |
| public_subnet_ids | Public subnet IDs (internet-facing load balancers). |
| vpc_id | VPC ID. |
<!-- END_TF_DOCS -->

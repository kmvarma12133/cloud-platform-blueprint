# IAM and interruption handling for Karpenter. The Karpenter Helm release itself
# is deployed by Argo CD (platform/gitops/apps/karpenter.yaml); Terraform owns
# only the cloud-side pieces it needs.

resource "aws_iam_role" "karpenter_node" {
  name               = "${var.cluster_name}-karpenter-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
    "AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value}"
}

resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"
}

# Controller identity via EKS Pod Identity (no OIDC trust-policy juggling).
data "aws_iam_policy_document" "karpenter_controller_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "${var.cluster_name}-karpenter-controller"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume.json
  tags               = var.tags
}

locals {
  # EC2 ARN prefix for this region. The controller policy below follows the
  # upstream Karpenter reference policy: scoped to resource types plus tag
  # conditions, so it can only create and delete capacity it tagged itself.
  ec2_arn       = "arn:${local.partition}:ec2:${data.aws_region.current.name}"
  owned_tag_key = "kubernetes.io/cluster/${var.cluster_name}"
}

data "aws_iam_policy_document" "karpenter_controller" {
  # AMIs, snapshots, subnets and SGs are shared inputs to a launch, not things
  # Karpenter creates, so they carry no tag condition.
  statement {
    sid     = "LaunchWithSharedResources"
    actions = ["ec2:RunInstances", "ec2:CreateFleet"]
    resources = [
      "${local.ec2_arn}::image/*",
      "${local.ec2_arn}::snapshot/*",
      "${local.ec2_arn}:*:security-group/*",
      "${local.ec2_arn}:*:subnet/*",
      "${local.ec2_arn}:*:capacity-reservation/*",
    ]
  }

  # Launch templates must already belong to this cluster and a NodePool.
  statement {
    sid       = "LaunchWithOwnedTemplates"
    actions   = ["ec2:RunInstances", "ec2:CreateFleet"]
    resources = ["${local.ec2_arn}:*:launch-template/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.owned_tag_key}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  # Anything Karpenter creates must be tagged as owned by this cluster at creation.
  statement {
    sid     = "CreateTaggedCapacity"
    actions = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
    resources = [
      "${local.ec2_arn}:*:fleet/*",
      "${local.ec2_arn}:*:instance/*",
      "${local.ec2_arn}:*:volume/*",
      "${local.ec2_arn}:*:network-interface/*",
      "${local.ec2_arn}:*:launch-template/*",
      "${local.ec2_arn}:*:spot-instances-request/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/${local.owned_tag_key}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid     = "TagOnCreate"
    actions = ["ec2:CreateTags"]
    resources = [
      "${local.ec2_arn}:*:fleet/*",
      "${local.ec2_arn}:*:instance/*",
      "${local.ec2_arn}:*:volume/*",
      "${local.ec2_arn}:*:network-interface/*",
      "${local.ec2_arn}:*:launch-template/*",
      "${local.ec2_arn}:*:spot-instances-request/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/${local.owned_tag_key}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
    }
  }

  # After launch Karpenter only adds its NodeClaim name and the Name tag.
  statement {
    sid       = "TagOwnedInstances"
    actions   = ["ec2:CreateTags"]
    resources = ["${local.ec2_arn}:*:instance/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.owned_tag_key}"
      values   = ["owned"]
    }
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["eks:eks-cluster-name", "karpenter.sh/nodeclaim", "Name"]
    }
  }

  statement {
    sid     = "DeleteOwnedCapacity"
    actions = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
    resources = [
      "${local.ec2_arn}:*:instance/*",
      "${local.ec2_arn}:*:launch-template/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.owned_tag_key}"
      values   = ["owned"]
    }
  }

  # EC2 Describe calls do not support resource-level permissions; pinning the
  # region is the tightest scope available.
  statement {
    sid = "RegionalReadOnly"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [data.aws_region.current.name]
    }
  }

  # Public AMI parameters, e.g. the latest Bottlerocket image ID.
  statement {
    sid       = "ResolveAmiParameters"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:${local.partition}:ssm:${data.aws_region.current.name}::parameter/aws/service/*"]
  }

  statement {
    sid       = "PricingForSpotDecisions"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  statement {
    sid       = "DiscoverApiEndpoint"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.this.arn]
  }

  statement {
    sid       = "PassNodeRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.karpenter_node.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid = "ManageInstanceProfiles"
    actions = [
      "iam:CreateInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
    ]
    resources = ["arn:${local.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"]
  }

  statement {
    sid = "InterruptionQueue"
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
  }
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name   = "karpenter-controller"
  role   = aws_iam_role.karpenter_controller.id
  policy = data.aws_iam_policy_document.karpenter_controller.json
}

resource "aws_eks_pod_identity_association" "karpenter" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "karpenter"
  service_account = "karpenter"
  role_arn        = aws_iam_role.karpenter_controller.arn
}

# Spot interruption / rebalance / health events -> SQS -> Karpenter drains early.
resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${var.cluster_name}-karpenter"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

data "aws_iam_policy_document" "karpenter_queue" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.url
  policy    = data.aws_iam_policy_document.karpenter_queue.json
}

locals {
  karpenter_events = {
    spot_interruption = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Spot Instance Interruption Warning"]
    }
    rebalance = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance Rebalance Recommendation"]
    }
    state_change = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance State-change Notification"]
    }
    health = {
      source      = ["aws.health"]
      detail-type = ["AWS Health Event"]
    }
  }
}

resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each      = local.karpenter_events
  name          = "${var.cluster_name}-karpenter-${replace(each.key, "_", "-")}"
  event_pattern = jsonencode(each.value)
  tags          = var.tags
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each = local.karpenter_events
  rule     = aws_cloudwatch_event_rule.karpenter[each.key].name
  arn      = aws_sqs_queue.karpenter_interruption.arn
}

# Karpenter-launched nodes need the EKS-managed cluster security group to reach
# the control plane. EKS creates that group itself, so it is tagged here for the
# EC2NodeClass securityGroupSelectorTerms to discover.
resource "aws_ec2_tag" "cluster_sg_discovery" {
  resource_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

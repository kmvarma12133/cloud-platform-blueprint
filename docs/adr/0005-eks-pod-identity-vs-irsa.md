# 0005: EKS Pod Identity by default, IRSA where it fits better

- Status: accepted
- Date: 2026-10-20

## Context and problem statement

Several in-cluster components call AWS APIs: Karpenter (EC2, SQS, IAM instance
profiles), External Secrets (Secrets Manager) and the EBS CSI driver (EC2
volumes). Each needs its own least-privilege credentials. The node's instance
role is not an option, because every pod on the node would inherit it. That is
also why the Karpenter node class sets an IMDS hop limit of 1.

EKS offers two ways to map a Kubernetes service account to an IAM role.

## Considered options

1. **IRSA.** The cluster's OIDC issuer is an IAM identity provider. Each role's
   trust policy names that issuer plus `system:serviceaccount:<ns>:<sa>`, and
   the pod gets a projected token that it exchanges with STS.
2. **EKS Pod Identity.** Roles trust the `pods.eks.amazonaws.com` service
   principal. The mapping from (cluster, namespace, service account) to role is
   an `aws_eks_pod_identity_association`. The Pod Identity Agent DaemonSet hands
   pods their credentials.

## Decision outcome

Pod Identity for components this repo installs and configures itself:
Karpenter and External Secrets. IRSA is kept for the EBS CSI driver, which is
configured through the managed add-on's `service_account_role_arn`. That leaves
one worked example of each model side by side in `infra/modules/aws-eks`.
Moving the add-on to Pod Identity is a small change, since `aws_eks_addon`
accepts a `pod_identity_association` block.

Why Pod Identity is the default:

- **Reusable trust policy.** It's identical for every cluster, with no
  cluster-specific OIDC URL inside. The same role can be associated in several
  clusters, and rebuilding a cluster doesn't mean editing IAM trust policies.
- **Mapping managed through the EKS API.** The mapping lives in Terraform next
  to the cluster. Nothing has to be annotated on the service account (which
  Argo CD would also manage), and the karpenter chart needs no IRSA
  annotation.
- **Session tags.** STS sessions carry the cluster, namespace and service
  account as tags, so policies can use attribute-based conditions.
- **No OIDC provider limit.** Each cluster no longer consumes one of the
  account's IAM OIDC providers.

### Consequences

Good:

- No `eks.amazonaws.com/role-arn` annotations in Git-managed manifests.
- Every role in the module shares one trust policy document.

Bad:

- The Pod Identity Agent add-on must be running before pods start. It's
  installed as a managed add-on in the module.
- Pod Identity is EKS-only and doesn't cover Fargate pods. IRSA remains the
  portable option, for example for self-managed clusters or cross-account
  patterns that rely on an OIDC trust.
- Applications need an AWS SDK recent enough to use the container
  credentials provider. Current SDKs all do.

## Azure equivalent

AKS workload identity works like IRSA: the OIDC issuer is enabled in
`infra/modules/azure-aks`, and a user-assigned managed identity gets a
federated credential for `system:serviceaccount:<ns>:<sa>`. The service account
carries `azure.workload.identity/client-id`. The aks-dev overlay sets this for
External Secrets reading Key Vault. There is no Azure counterpart to Pod
Identity's association API.

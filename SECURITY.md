# Security policy

## Reporting a vulnerability

Please report security issues privately through GitHub's
[private vulnerability reporting](https://github.com/Kmvarma12133/cloud-platform-blueprint/security/advisories/new),
not in a public issue or pull request. Include what you found, how to
reproduce it, and the affected path or commit.

You can expect an acknowledgement within 3 working days and an assessment
within 10. Fixes are released on `main`; this repository has no versioned
releases to backport to.

## Scope

In scope:

- the Terraform modules, Terragrunt configuration and Kubernetes manifests in
  this repository, where using them as documented would leave a deployment
  insecure (for example, an IAM policy broader than described, or a policy
  that fails to enforce what its tests claim);
- the CI workflows (for example, script injection or token exposure);
- the `orders-api` reference service.

Out of scope:

- vulnerabilities in upstream projects (Argo CD, Karpenter, Gatekeeper and so
  on). Please report those upstream. If our pinned version is affected, an issue
  asking for a bump is welcome;
- findings that need already-privileged access, such as cluster-admin or
  account administrator;
- the placeholder values (account IDs, CIDR allowlists) that must be replaced
  before use.

## How this repository protects itself

- GitHub Actions are pinned to full commit SHAs, and each job has minimal
  `permissions`. Downloaded tools are verified by SHA-256.
- Images are scanned with Trivy (builds fail on fixable CRITICAL or HIGH),
  signed keylessly with Cosign, and carry a signed SPDX SBOM attestation.
  Promotion to prod verifies both.
- CI holds no cloud or cluster credentials. Argo CD pulls from Git, and the
  sketched Terraform plan job uses GitHub OIDC.
- `pre-commit` runs gitleaks and detect-private-key. Dependabot proposes
  weekly updates for Python, Docker, Actions and Terraform providers.

# 0002: Terragrunt to keep environments DRY

- Status: accepted
- Date: 2026-10-20

## Context and problem statement

The same Terraform modules (`aws-vpc`, `aws-eks`, `azure-aks`) are deployed
to several environments that differ only in inputs: CIDR, NAT topology, node
counts, endpoint exposure and log retention. Dev and prod live in separate AWS
accounts. Each component needs its own state, with a backend and provider
configuration that is identical apart from the account and region.

Plain Terraform has no way to share the `backend` and `provider` blocks across
root modules, and a root module cannot read another root module's outputs
without a remote-state data source.

## Decision drivers

- An environment's differences should fit on one screen.
- Separate state per component and environment, so a bad VPC apply cannot
  touch the EKS state and dev cannot touch prod.
- It must be impossible to apply dev configuration with prod credentials, or
  the reverse.
- Cross-component wiring (EKS needs the VPC's subnet IDs) without
  copy-pasted IDs.

## Considered options

1. A plain Terraform root module per environment, with backend and provider
   blocks copied into each.
2. Terraform workspaces over one root module.
3. Terragrunt.
4. HCP Terraform Stacks.

## Decision outcome

Option 3, Terragrunt, laid out as follows:

- **`infra/live/root.hcl`** generates the S3 backend for every AWS unit. The
  state key is derived from the unit's path, normalised to forward slashes so
  Windows and Linux operators address the same object. Locking uses S3-native
  lock files. It also generates the AWS provider with `default_tags` and
  `allowed_account_ids` pinned to the environment's account.
- **`infra/live/aws/<env>/env.hcl`** holds everything that differs between
  environments.
- **`infra/live/_envcommon/*.hcl`** maps `env.hcl` onto module inputs once.
- **Each unit** (`aws/dev/vpc/terragrunt.hcl`, ...) is two includes and
  nothing else.
- **The EKS unit** declares `dependency "vpc"` with `mock_outputs`, so `init`,
  `validate` and `plan` run before the VPC exists. Apply always uses the real
  outputs.
- **The Azure unit** doesn't include `root.hcl`. Its state lives in Azure
  Storage, so it generates its own `azurerm` backend and provider.

### Consequences

Good:

- Adding an environment means copying a directory and editing `env.hcl`.
- The provider refuses to run against the wrong account.
- `terragrunt run --all plan` walks the dependency graph.
- CI checks each unit's inputs against the module's variables with
  `terragrunt hcl validate --inputs --strict`, without credentials.

Bad:

- One more tool, and its version has to be managed alongside Terraform's.
- Generated `backend.tf` and `provider.tf` live in `.terragrunt-cache`. Newcomers
  need to know where to look.
- Mock outputs can hide wiring mistakes until the first real plan. They are
  restricted to `init`, `validate` and `plan`.

## Pros and cons of the other options

**Copy-paste root modules.** No extra tool, but backend and provider blocks
drift between environments, and cross-module wiring needs
`terraform_remote_state` with hard-coded bucket and key names.

**Workspaces.** One configuration with multiple states in the same backend.
That doesn't fit separate AWS accounts with separate credentials and
backends, and it makes "which workspace am I in?" an easy mistake with prod
consequences.

**HCP Terraform Stacks.** Solves the same problem natively, but ties the
workflow to HCP Terraform. That's a reasonable choice for an organisation
already using it, and an unnecessary dependency for a reference repo that
should run with open-source tools.

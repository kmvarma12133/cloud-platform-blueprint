# 0001: Argo CD GitOps instead of push-based deploys

- Status: accepted
- Date: 2026-10-20

## Context and problem statement

The platform runs several clusters (EKS dev and prod, AKS dev, and kind for
local work). Each needs the same set of add-ons plus the application, with
small per-cluster differences. Changes have to be reviewable, reproducible and
easy to roll back, and someone on call needs to see what is deployed and
whether it matches what was intended.

The usual starting point is for CI to run `helm upgrade` or `kubectl apply`
against each cluster. That gives CI cluster-admin credentials for every
environment and leaves no mechanism to notice when a cluster drifts from what
CI last applied.

## Decision drivers

- CI must not hold credentials that can change a cluster.
- One audit trail for "what changed, who approved it, when": Git history.
- Drift (manual `kubectl edit`, a deleted resource) must be visible and
  corrected automatically outside prod.
- Promotion between environments should be a reviewed change, not a pipeline
  re-run.
- It must work the same way on EKS, AKS and kind.

## Considered options

1. Push: CI runs Helm or kubectl with per-cluster credentials.
2. Argo CD (pull), app-of-apps plus ApplicationSet.
3. Flux CD (pull), Kustomization and HelmRelease resources.

## Decision outcome

Option 2, Argo CD. Each cluster runs its own Argo CD, bootstrapped once with
`platform/gitops/bootstrap/argocd` and a single root Application. That root app
renders `platform/gitops/clusters/<cluster>`, which composes the shared
`apps/` base with cloud-specific pieces through Kustomize. CI's only write
access is to this Git repository: it commits the new image tag to
`values-dev.yaml`, and Argo CD does the rest.

- Dev Applications sync automatically with `prune` and `selfHeal`.
- In the prod overlay every Application has automated sync removed, so a
  merged change waits as OutOfSync until a person syncs it.
- Add-ons install in sync waves (CRDs, then operators, then their consumers).
  A custom health check for `Application` resources makes each wave wait for
  the previous one to be healthy.

### Consequences

Good:

- No kubeconfig or cloud credentials for the clusters exist in CI.
- Rollback is `git revert`. Prod drift shows in the UI rather than being
  silently fixed.
- One Argo CD per cluster contains the blast radius: a compromised dev Argo CD
  cannot touch prod.

Bad:

- Argo CD itself becomes critical infrastructure that needs upgrades, RBAC and
  backups. Its install is a pinned kustomization of the upstream manifest so
  that it too can be managed from Git.
- Secrets cannot live in Git. External Secrets pulls them from AWS Secrets
  Manager or Azure Key Vault (see `platform/secrets`).
- CI image-tag commits add noise to `main`'s history.
- Sync is eventually consistent. Argo CD polls every three minutes unless a
  Git webhook is configured.

## Pros and cons of the other options

**Push from CI.** Simple and familiar, but every pipeline holds cluster-admin
for every environment it deploys to. Nothing reconciles drift, and a
"deployment" is whatever the last pipeline run happened to apply.

**Flux CD.** Technically equivalent for pull-based reconciliation, and lighter
to run. Argo CD was chosen for its UI, which on-call engineers and reviewers of
this repo use to see sync and health at a glance. It also has ApplicationSet
generators, and it integrates directly with Argo Rollouts, so canary steps and
analysis runs appear in the same UI.

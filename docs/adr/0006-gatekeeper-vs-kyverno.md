# 0006: Gatekeeper with tested Rego, rather than Kyverno

- Status: accepted
- Date: 2026-10-20

## Context and problem statement

Every workload must meet a baseline before it runs:

- CPU and memory limits;
- no `:latest` or untagged images;
- `runAsNonRoot`;
- images only from approved registries (our ECR, ACR and GHCR namespace);
- `app.kubernetes.io/name` and `owner` labels.

The rules have to be reviewable, unit-tested, enforced at admission, and
reported on for resources that already exist. Teams also need time to fix
violations before enforcement starts.

## Considered options

1. OPA Gatekeeper (Rego).
2. Kyverno (YAML policies, CEL).
3. Kubernetes ValidatingAdmissionPolicy (built-in CEL, GA since 1.30).
4. Azure Policy for AKS, plus its EKS equivalent.

## Decision outcome

Option 1, Gatekeeper, with the policy source kept in plain `.rego` files.

- **Source and tests.** `platform/policies/rego/*.rego` are ordinary OPA
  policies with `opa test` unit tests: 27 tests, covering edge cases such as
  registry ports mistaken for tags and digest-pinned images. A shared library
  extracts containers from Pods and from every workload kind, including
  Rollouts, so a bad Deployment is rejected when it's applied rather than when
  its ReplicaSet fails.
- **Generated templates.** `scripts/build-gatekeeper.py` wraps each policy in
  a `ConstraintTemplate`, using the kind and parameter schema from the policy's
  `METADATA` block. CI fails if the generated templates drift from the source.
- **Staged enforcement.** Constraints share one base. The dev overlay sets
  `enforcementAction: dryrun`: violations show in the audit and nothing is
  blocked. Prod sets `deny`.

On AKS the Azure Policy add-on already runs a managed Gatekeeper. A second,
self-managed Gatekeeper would fight it over the same webhooks and CRDs, so the
aks-dev overlay doesn't install ours. There, the same rules are assigned as
Azure Policy definitions. Built-in Kubernetes definitions exist for resource
limits, allowed images, allowed user IDs and required labels, and custom ones
can carry our Rego.

### Consequences

Good:

- Policies are code with tests, reviewed like any other change.
- The same Rego can run in CI with `conftest` against rendered manifests,
  catching problems before anything reaches a cluster.
- The dryrun-to-deny path gives teams a real migration window.

Bad:

- Rego is a language to learn. Kyverno policies are easier to read for people
  new to policy-as-code.
- Gatekeeper's webhook fails open by default (`failurePolicy: Ignore`), so
  while the webhook is down, resources are admitted unchecked. The audit
  catches them afterwards.
- Platform namespaces are excluded from the constraints. Those components come
  from pinned, reviewed upstream charts, which don't follow our labelling
  convention.

## Pros and cons of the other options

**Kyverno.** YAML policies, mutation and generation built in, image signature
verification (`verifyImages`), and its own test CLI. For many teams it's the
simpler choice. Gatekeeper won here because the same Rego is reusable across
the OPA ecosystem, from CI checks to other admission points, and because
`opa test` is a mature unit-test runner.

**ValidatingAdmissionPolicy.** No webhook to run and good for simple rules,
but it doesn't audit existing resources and has no external data. Simple rules
could move to it later. Gatekeeper can generate VAP resources from templates.

**Azure Policy.** The right tool on AKS (and used there), but not portable to
EKS or kind.

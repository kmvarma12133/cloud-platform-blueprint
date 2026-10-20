#!/usr/bin/env bash
# Offline validation of everything under platform/. Used by `make k8s-validate`
# and .github/workflows/k8s.yml.
#
#   1. helm lint + helm template of the orders-api chart for every values file
#   2. kustomize build of every overlay (GitOps clusters, policies, Karpenter,
#      gateway, secrets, observability)
#   3. kubeconform -strict on all of it, with the datreeio CRDs catalog so
#      Rollouts, ScaledObjects, ServiceMonitors, NodePools etc. are validated
#      too. Gatekeeper Constraint kinds are generated from the templates at
#      runtime, so they have no published schema and are skipped.
#
# Rendering the upstream add-on charts needs network access and is slower; it
# lives in scripts/render-addons.py (`make k8s-validate-addons`).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CHART=platform/charts/orders-api
CRDS_CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
KUBECONFORM=(kubeconform -strict -summary -output text
  -schema-location default -schema-location "$CRDS_CATALOG"
  -skip "K8sRequiredLimits,K8sDisallowLatestTag,K8sRequireNonRoot,K8sAllowedRegistries,K8sRequiredLabels")

section() { printf '\n== %s\n' "$*"; }

section "helm lint"
helm lint "$CHART" -f "$CHART/values-dev.yaml"
helm lint "$CHART" -f "$CHART/values-prod.yaml"

section "helm template | kubeconform"
# Each environment on its own, then layered the way the local profiles use it.
render() {
  local env=$1 label=$2; shift 2
  printf '%-34s' "orders-api ($env, $label)"
  helm template orders-api "$CHART" -n "orders-$env" -f "$CHART/values-$env.yaml" "$@" | "${KUBECONFORM[@]}" -
}
for env in dev prod; do
  render "$env" cloud
  render "$env" local -f "$CHART/values-local.yaml"
  render "$env" local-lite -f "$CHART/values-local.yaml" -f "$CHART/values-local-lite.yaml"
done

section "kustomize build | kubeconform"
overlays=(
  platform/gitops/clusters/*/
  platform/policies/gatekeeper/constraints/dev
  platform/policies/gatekeeper/constraints/prod
  platform/karpenter/overlays/*/
  platform/gateway/overlays/local
  platform/gateway/overlays/dev
  platform/gateway/overlays/prod
  platform/secrets/aws
  platform/secrets/azure
  platform/secrets/local
  platform/observability
)
for dir in "${overlays[@]}"; do
  printf '%-48s' "${dir%/}"
  kubectl kustomize "$dir" | "${KUBECONFORM[@]}" -
done

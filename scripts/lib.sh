# Helpers shared by the local demo scripts. Sourced, not executed.
# shellcheck shell=bash

CLUSTER_NAME="${CLUSTER_NAME:-cpb}"
KUBE_CONTEXT="kind-${CLUSTER_NAME}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

need() {
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required but not on PATH"
  done
}

# Every kubectl call targets the kind cluster explicitly, so the scripts can
# never act on whatever cluster the current context happens to point at.
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }

# Set (or clear) the image.tag Helm parameter on a generated Application. The
# local GitOps overlay tells the ApplicationSet to leave this field alone, so
# the override sticks until it is cleared. Argo CD then syncs dev on its own,
# which starts a canary.
set_image_tag() {
  local app=$1 tag=$2
  if [ -z "$tag" ]; then
    k -n argocd patch application "$app" --type json \
      -p '[{"op":"remove","path":"/spec/source/helm/parameters"}]' >/dev/null 2>&1 || true
  else
    k -n argocd patch application "$app" --type merge \
      -p "{\"spec\":{\"source\":{\"helm\":{\"parameters\":[{\"name\":\"image.tag\",\"value\":\"$tag\"}]}}}}" >/dev/null
  fi
}

current_image() {
  k -n "$1" get rollout orders-api -o jsonpath='{.spec.template.spec.containers[0].image}'
}

# One status line per poll until the rollout finishes, aborts or times out.
# Returns 0 when the new version is fully promoted, 1 when the rollout aborts.
watch_rollout() {
  local ns=$1 timeout=${2:-900} start=$SECONDS
  local phase step aborted weight canary stable analysis i steps
  # The weight each step sets, empty for pause and analysis steps: "10,,30,,60,,100,"
  local -a weights
  IFS=, read -r -a weights <<<"$(k -n "$ns" get rollout orders-api \
    -o jsonpath='{range .spec.strategy.canary.steps[*]}{.setWeight}{","}{end}')"
  steps=${#weights[@]}

  while (( SECONDS - start < timeout )); do
    phase=$(k -n "$ns" get rollout orders-api -o jsonpath='{.status.phase}')
    step=$(k -n "$ns" get rollout orders-api -o jsonpath='{.status.currentStepIndex}')
    aborted=$(k -n "$ns" get rollout orders-api -o jsonpath='{.status.abort}')

    # The canary weight is the last setWeight at or before the current step.
    weight=0
    for (( i = ${step:-0} < steps ? ${step:-0} : steps - 1; i >= 0; i-- )); do
      if [ -n "${weights[$i]}" ]; then weight=${weights[$i]}; break; fi
    done

    canary=$(k -n "$ns" get pods -l role=canary --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
    stable=$(k -n "$ns" get pods -l role=stable --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
    analysis=$(k -n "$ns" get analysisrun --sort-by=.metadata.creationTimestamp \
      -o jsonpath='{range .items[-1:]}{.metadata.name}={.status.phase}{end}' 2>/dev/null)

    printf '%s  phase=%-11s step=%s/%s weight=%s%%  pods stable=%s canary=%s  analysis=%s\n' \
      "$(date +%H:%M:%S)" "${phase:-?}" "${step:-0}" "$steps" "$weight" "$stable" "$canary" "${analysis:--}"

    if [ "$aborted" = "true" ]; then return 1; fi
    if [ "$phase" = "Healthy" ] && [ "${step:-0}" = "$steps" ]; then return 0; fi
    sleep 10
  done
  warn "timed out after ${timeout}s"
  return 2
}

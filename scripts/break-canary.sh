#!/usr/bin/env bash
# The headline demo: ship a bad version and watch the platform refuse it.
#
# Deploys the local-broken image (half of all API calls return 500, while the
# health probes stay green so Kubernetes alone would happily promote it) under
# steady load. The canary takes 10% of traffic, pauses, moves to 30%, and the
# Prometheus analysis then measures a success rate far below 99% on the canary
# pods only. Argo Rollouts aborts and scales the canary away; the stable
# version never stops serving.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

NS=orders-dev
APP=orders-api-dev
need kubectl

phase=$(k -n "$NS" get rollout orders-api -o jsonpath='{.status.phase}')
[ "$phase" = "Healthy" ] || die "Rollout is $phase; run 'make demo-reset' first"
stable_image=$(current_image "$NS")

log "Starting load so the analysis has traffic to measure"
DURATION=10m "$ROOT/scripts/load-test.sh"

log "Deploying local-broken over ${stable_image##*:}"
set_image_tag "$APP" local-broken
wait_for_image "$NS" local-broken

set +e
watch_rollout "$NS" 900
result=$?
set -e

case $result in
  1)
    log "Rollout ABORTED by the canary analysis. What it measured:"
    run=$(k -n "$NS" get analysisrun --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')
    k -n "$NS" get analysisrun "$run" -o jsonpath='{range .status.metricResults[*]}{"  "}{.name}{": "}{.phase}{"  measurements="}{range .measurements[*]}{.value}{" "}{end}{"\n"}{end}'
    echo
    log "Pods now (the canary has been scaled away):"
    k -n "$NS" get pods -l app.kubernetes.io/name=orders-api \
      -o custom-columns=POD:.metadata.name,ROLE:.metadata.labels.role,IMAGE:.spec.containers[0].image,READY:.status.containerStatuses[0].ready
    echo
    log "Users kept being served by the stable version. Restore a clean state with: make demo-reset"
    ;;
  0) die "The broken version was promoted; the analysis did not catch it" ;;
  *) die "Timed out waiting for the analysis" ;;
esac

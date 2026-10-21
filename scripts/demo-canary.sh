#!/usr/bin/env bash
# Happy path: roll a healthy new version through the canary steps.
#
# Switches orders-api in dev between the local-v1 and local-v2 images (both
# healthy) under steady load, then follows the Rollout step by step:
# 10% -> 2m pause -> 30% -> analysis -> 60% -> analysis -> 100%.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

NS=orders-dev
APP=orders-api-dev
need kubectl

current=$(current_image "$NS")
case "$current" in
  *:local-v2) next=local-v1 ;;
  *) next=local-v2 ;;
esac

log "Starting load so the analysis has traffic to measure"
DURATION=15m "$ROOT/scripts/load-test.sh"

log "Deploying $next (currently ${current##*:})"
set_image_tag "$APP" "$next"
wait_for_image "$NS" "$next"

if watch_rollout "$NS" 900; then
  log "Promoted: every pod now runs $(current_image "$NS" | sed 's/.*://')"
  k -n "$NS" get analysisrun -o custom-columns=ANALYSIS:.metadata.name,PHASE:.status.phase,STARTED:.metadata.creationTimestamp
else
  warn "The rollout did not complete; inspect it with: kubectl -n $NS describe rollout orders-api"
  exit 1
fi

#!/usr/bin/env bash
# Return the dev Rollout to a clean, Healthy state after a demo.
#
# Points the Application back at the image the stable ReplicaSet is running.
# Because that matches the stable revision, Argo Rollouts goes straight back to
# Healthy without starting another canary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

NS=orders-dev
need kubectl

hash=$(k -n "$NS" get rollout orders-api -o jsonpath='{.status.stableRS}')
image=$(k -n "$NS" get rs -l "rollouts-pod-template-hash=$hash" -o jsonpath='{.items[0].spec.template.spec.containers[0].image}')
log "Resetting orders-api-dev to the stable image ${image##*:}"
set_image_tag orders-api-dev "${image##*:}"
k -n load-test delete job k6 --ignore-not-found >/dev/null
sleep 10
k -n "$NS" get rollout orders-api -o jsonpath='{"phase: "}{.status.phase}{"\n"}'

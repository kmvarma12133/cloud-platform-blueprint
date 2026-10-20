#!/usr/bin/env bash
# Delete the local kind cluster and everything in it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

need kind
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  log "Deleting kind cluster '$CLUSTER_NAME'"
  kind delete cluster --name "$CLUSTER_NAME"
else
  log "No kind cluster named '$CLUSTER_NAME'"
fi

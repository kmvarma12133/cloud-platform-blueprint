#!/usr/bin/env bash
# Bring up the whole platform on a local kind cluster, the GitOps way:
#
#   kind cluster -> Argo CD -> one root Application -> everything else from Git
#
# Requirements: docker, kind, kubectl. About 10 minutes on a first run.
#
# Environment:
#   LOCAL_PROFILE  local | local-lite (default: chosen from Docker's memory)
#   LOCAL_GIT=1    serve this checkout's HEAD to Argo CD from inside the cluster
#                  instead of GitHub, e.g. to try a branch that is not pushed
#   REPO_URL       Git URL Argo CD syncs from when LOCAL_GIT is not set
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

GITHUB_REPO_URL="https://github.com/Kmvarma12133/cloud-platform-blueprint.git"
REPO_URL="${REPO_URL:-$GITHUB_REPO_URL}"
IMAGE="localhost/orders-api" # matches values-local.yaml

need docker kind kubectl git
docker info >/dev/null 2>&1 || die "Docker is not running"

# --- Profile -----------------------------------------------------------------
if [ -z "${LOCAL_PROFILE:-}" ]; then
  mem_bytes=$(docker info --format '{{.MemTotal}}')
  if (( mem_bytes < 7 * 1024 * 1024 * 1024 )); then LOCAL_PROFILE=local-lite; else LOCAL_PROFILE=local; fi
  log "Docker has $(( mem_bytes / 1024 / 1024 )) MiB of memory: using the $LOCAL_PROFILE profile"
fi
[ -d "$ROOT/platform/gitops/clusters/$LOCAL_PROFILE" ] || die "unknown LOCAL_PROFILE: $LOCAL_PROFILE"

# --- Cluster -----------------------------------------------------------------
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  log "kind cluster '$CLUSTER_NAME' already exists"
else
  log "Creating kind cluster '$CLUSTER_NAME' (1 control plane, 2 workers in two 'zones')"
  kind create cluster --config "$ROOT/scripts/kind-config.yaml" --wait 120s
fi

# --- Images ------------------------------------------------------------------
# Three tags for the demos: v1 (initial), v2 (a healthy new version) and
# broken (v1 with FAULT_ERROR_RATE=0.5, half of all API calls return 500).
log "Building orders-api images"
docker build --quiet --build-arg VERSION=local-v1 -t "$IMAGE:local-v1" "$ROOT/app" >/dev/null
docker build --quiet --build-arg VERSION=local-v2 -t "$IMAGE:local-v2" "$ROOT/app" >/dev/null
printf 'FROM %s\nENV FAULT_ERROR_RATE=0.5 SERVICE_VERSION=local-broken\n' "$IMAGE:local-v1" |
  docker build --quiet -t "$IMAGE:local-broken" - >/dev/null
kind load docker-image --name "$CLUSTER_NAME" "$IMAGE:local-v1" "$IMAGE:local-v2" "$IMAGE:local-broken" >/dev/null 2>&1

# --- Argo CD -----------------------------------------------------------------
log "Installing Argo CD v3.5.5"
k apply --server-side --force-conflicts -k "$ROOT/platform/gitops/bootstrap/argocd" >/dev/null
k -n argocd rollout status deploy/argocd-repo-server --timeout=300s >/dev/null
k -n argocd rollout status deploy/argocd-applicationset-controller --timeout=300s >/dev/null
k -n argocd rollout status statefulset/argocd-application-controller --timeout=300s >/dev/null

# --- Git source --------------------------------------------------------------
if [ "${LOCAL_GIT:-0}" = "1" ]; then
  "$ROOT/scripts/local-git-server.sh"
  REPO_URL="http://git-server.git-server.svc/cgi-bin/git/cloud-platform-blueprint.git"
fi
case "$REPO_URL" in
  *github.com/OWNER/*) die "REPO_URL still contains the OWNER placeholder; set REPO_URL or use LOCAL_GIT=1" ;;
esac

# --- Root application --------------------------------------------------------
log "Applying the root Application (path platform/gitops/clusters/$LOCAL_PROFILE, repo $REPO_URL)"
sed -e "s|$GITHUB_REPO_URL|$REPO_URL|" \
  -e "s|path: platform/gitops/clusters/.*|path: platform/gitops/clusters/$LOCAL_PROFILE|" \
  "$ROOT/platform/gitops/bootstrap/root-app.yaml" | k apply -f - >/dev/null

# --- Wait for the platform ---------------------------------------------------
# orders-api-prod is excluded: prod never syncs on its own, by design.
log "Waiting for Argo CD to sync the platform (sync waves run in order)"
deadline=$(( SECONDS + 1200 ))
while :; do
  apps=$(k -n argocd get applications -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.sync.status}{" "}{.status.health.status}{"\n"}{end}' 2>/dev/null || true)
  pending=$(echo "$apps" | awk 'NF && $1 != "orders-api-prod" && !($2 == "Synced" && $3 == "Healthy")' | awk '{print $1"("$2"/"$3")"}' | tr '\n' ' ')
  total=$(echo "$apps" | awk 'NF' | wc -l | tr -d ' ')
  if [ -z "$pending" ] && echo "$apps" | grep -q '^orders-api-dev Synced Healthy'; then
    log "All $total Applications are synced and healthy"
    break
  fi
  (( SECONDS > deadline )) && { k -n argocd get applications; die "platform did not become healthy within 20 minutes"; }
  printf '   %s waiting: %s\n' "$(date +%H:%M:%S)" "${pending:-root app}"
  sleep 20
done

# Prod waits for a person. Do the first sync now so both environments run;
# later changes to prod show as OutOfSync until someone syncs them.
log "Syncing orders-api-prod once (the equivalent of pressing Sync in the UI)"
k -n argocd patch application orders-api-prod --type merge \
  -p '{"operation":{"initiatedBy":{"username":"local-up"},"sync":{"revision":"main"}}}' >/dev/null

argocd_password=$(k -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
grafana_password=$(k -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d)

cat <<EOF

Platform is up (profile: $LOCAL_PROFILE). In separate terminals:

  Argo CD        kubectl --context $KUBE_CONTEXT -n argocd port-forward svc/argocd-server 8080:443
                 https://localhost:8080   admin / $argocd_password
  Grafana        kubectl --context $KUBE_CONTEXT -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
                 http://localhost:3000    admin / $grafana_password   (dashboard: "orders-api SLO")
  Rollouts UI    kubectl --context $KUBE_CONTEXT -n argo-rollouts port-forward svc/argo-rollouts-dashboard 3100:3100
                 http://localhost:3100/rollouts/orders-dev
  orders-api     kubectl --context $KUBE_CONTEXT -n orders-dev port-forward svc/orders-api 8081:80
                 curl localhost:8081/version

Then:  make demo-canary     # healthy version, promoted step by step
       make demo-rollback   # broken version, aborted and rolled back automatically
EOF

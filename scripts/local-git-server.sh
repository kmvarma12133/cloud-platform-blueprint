#!/usr/bin/env bash
# Serve this checkout's HEAD to Argo CD from inside the kind cluster, so the
# demo runs from a branch or fork that is not on GitHub (used by
# `LOCAL_GIT=1 make local-up`).
#
# A throwaway clone has its repoURLs rewritten to the in-cluster URL (so the
# AppProject source restrictions still hold), is converted to a bare repo and
# served over git's "dumb" HTTP protocol by a tiny static file server.
# Only committed changes are served.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

LOCAL_URL="http://git-server.git-server.svc/cloud-platform-blueprint.git"
# Resolve HEAD once, so a commit made while this runs cannot split the packaging.
REV="$(git -C "$ROOT" rev-parse HEAD)"
IMAGE="cpb-local-git:${REV:0:12}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

log "Packaging ${REV:0:7} for the in-cluster git server"
git clone --quiet --no-local "$ROOT" "$work/src"
git -C "$work/src" fetch --quiet "$ROOT" "$REV"
git -C "$work/src" checkout --quiet -B main "$REV"
grep -rlE 'https://github\.com/[^/]+/cloud-platform-blueprint\.git' "$work/src/platform" |
  xargs sed -i -E "s#https://github\.com/[^/]+/cloud-platform-blueprint\.git#$LOCAL_URL#g"
git -C "$work/src" -c user.name=local-up -c user.email=local-up@localhost \
  commit --quiet -am "local: point Argo CD at the in-cluster git server"
git clone --quiet --bare "$work/src" "$work/cloud-platform-blueprint.git"
git -C "$work/cloud-platform-blueprint.git" update-server-info

cat >"$work/Dockerfile" <<'EOF'
FROM python:3.12.15-slim-trixie@sha256:a6e34c598f2467ed0e9a8d349809fcd8b5c603269512df273a0bb1784edc11b1
COPY cloud-platform-blueprint.git /srv/cloud-platform-blueprint.git
USER 65534
EXPOSE 8080
CMD ["python", "-m", "http.server", "8080", "--directory", "/srv"]
EOF
docker build --quiet -t "$IMAGE" "$work" >/dev/null
kind load docker-image --name "$CLUSTER_NAME" "$IMAGE" >/dev/null 2>&1

k apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: git-server
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: git-server
  namespace: git-server
  labels:
    app.kubernetes.io/name: git-server
    owner: platform-team
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: git-server
  template:
    metadata:
      labels:
        app.kubernetes.io/name: git-server
        owner: platform-team
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: git-server
          image: $IMAGE
          imagePullPolicy: Never
          ports:
            - containerPort: 8080
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          resources:
            requests: { cpu: 10m, memory: 32Mi }
            limits: { cpu: 200m, memory: 64Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: git-server
  namespace: git-server
spec:
  selector:
    app.kubernetes.io/name: git-server
  ports:
    - port: 80
      targetPort: 8080
EOF
k -n git-server rollout status deploy/git-server --timeout=120s >/dev/null
log "Serving $LOCAL_URL"

# Argo CD caches repository state; ask it to look again after a re-package.
k -n argocd annotate applications --all argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true

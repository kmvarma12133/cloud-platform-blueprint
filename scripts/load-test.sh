#!/usr/bin/env bash
# Drive steady traffic at orders-api from inside the cluster with k6.
#
# In-cluster on purpose: the Service spreads requests across stable and canary
# pods, which a kubectl port-forward (pinned to one pod) would not.
#
#   RATE=40 DURATION=5m TARGET=http://orders-api.orders-dev.svc scripts/load-test.sh
#   FOLLOW=1 scripts/load-test.sh     # stream k6 output until it finishes
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

RATE="${RATE:-40}"
DURATION="${DURATION:-5m}"
TARGET="${TARGET:-http://orders-api.orders-dev.svc}"
K6_IMAGE="grafana/k6:2.3.0@sha256:9c2dee7f8ed74d317e4027c06a10f169b625638189de8d4555d0b3486a5aeb34"

need kubectl
k create namespace load-test --dry-run=client -o yaml | k apply -f - >/dev/null
k -n load-test create configmap k6-orders --from-file=orders.js="$ROOT/scripts/k6/orders.js" \
  --dry-run=client -o yaml | k apply -f - >/dev/null
k -n load-test delete job k6 --ignore-not-found --wait >/dev/null

k apply -f - >/dev/null <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: k6
  namespace: load-test
  labels:
    app.kubernetes.io/name: k6
    owner: platform-team
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 600
  template:
    metadata:
      labels:
        app.kubernetes.io/name: k6
        owner: platform-team
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 12345
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: k6
          image: $K6_IMAGE
          args: ["run", "--quiet", "/scripts/orders.js"]
          env:
            - { name: TARGET, value: "$TARGET" }
            - { name: RATE, value: "$RATE" }
            - { name: DURATION, value: "$DURATION" }
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          resources:
            requests: { cpu: 100m, memory: 64Mi }
            limits: { cpu: 500m, memory: 256Mi }
          volumeMounts:
            - { name: script, mountPath: /scripts }
            - { name: tmp, mountPath: /tmp }
      volumes:
        - name: script
          configMap:
            name: k6-orders
        - name: tmp
          emptyDir: {}
YAML

log "k6: $RATE req/s against $TARGET for $DURATION (job load-test/k6)"
if [ "${FOLLOW:-0}" = "1" ]; then
  k -n load-test wait --for=condition=Ready pod -l job-name=k6 --timeout=120s >/dev/null
  k -n load-test logs -f job/k6
fi

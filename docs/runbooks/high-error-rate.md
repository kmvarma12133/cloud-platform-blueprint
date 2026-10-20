# Runbook: orders-api SLO burn (high error rate or latency)

Alerts that link here:

| Alert | Severity | Fires when |
|---|---|---|
| `OrdersApiErrorBudgetBurnFast` | page | 5xx ratio above 1.44% (14.4x burn) over both 1h and 5m |
| `OrdersApiErrorBudgetBurnSlow` | ticket | 5xx ratio above 0.6% (6x burn) over both 6h and 30m |
| `OrdersApiLatencyBudgetBurnFast` | page | more than 14.4% of requests slower than 300ms over 1h and 5m |
| `OrdersApiLatencyBudgetBurnSlow` | ticket | more than 6% of requests slower than 300ms over 6h and 30m |

SLOs: 99.9% of non-probe requests succeed, and 99% complete within 300ms,
over 30 days. A 14.4x burn spends 2% of the monthly budget per hour, so the
whole budget is gone in about two days.

## Symptoms

- A page or ticket with the alerts above, labelled with `namespace`
  (`orders-dev` or `orders-prod`).
- Users see 5xx responses or slow order creation.

## Dashboards and queries

Grafana → **orders-api SLO** (`/d/orders-api-slo`), with the environment
selected. Check "Error budget remaining", "Burn rate", "Error ratio" and
"Error ratio: canary vs stable".

```promql
# Error ratio by route and status, last 5m
sum by (route, status) (rate(http_requests_total{namespace="orders-prod", service="orders-api", status=~"5.."}[5m]))
  / ignoring(status) group_left sum by (route) (rate(http_requests_total{namespace="orders-prod", service="orders-api"}[5m]))

# Is it one pod, or all of them?
sum by (pod) (rate(http_requests_total{namespace="orders-prod", service="orders-api", status=~"5.."}[5m]))

# Canary vs stable (only meaningful during a rollout)
sum by (role) (rate(http_requests_total{namespace="orders-prod", service="orders-api", status=~"5.."}[5m]))
  / sum by (role) (rate(http_requests_total{namespace="orders-prod", service="orders-api"}[5m]))

# p95 latency by route
histogram_quantile(0.95, sum by (le, route) (rate(http_request_duration_seconds_bucket{namespace="orders-prod", service="orders-api"}[5m])))
```

## Diagnosis

1. **Did something just change?** Most incidents follow a change.

   ```bash
   kubectl -n orders-prod get rollout orders-api -o wide
   kubectl -n argocd get application orders-api-prod -o jsonpath='{.status.history[-1:]}'
   git log --oneline -5 -- platform/charts/orders-api/values-prod.yaml
   ```

   If a rollout is in progress, the canary analysis should catch it. Go to
   [canary aborted](canary-aborted.md) if it already has.
2. **One pod or all?** Errors on a single pod point to the node or the pod
   (OOM, a noisy neighbour). Errors on all pods point to the code, config or a
   dependency.

   ```bash
   kubectl -n orders-prod get pods -l app.kubernetes.io/name=orders-api -o wide
   kubectl -n orders-prod top pods -l app.kubernetes.io/name=orders-api
   kubectl -n orders-prod logs -l app.kubernetes.io/name=orders-api --since=15m | grep '"level": "error"'
   ```

3. **Saturation.** Check whether KEDA is at `maxReplicaCount`, or pods are
   CPU-throttled at their limit.

   ```bash
   kubectl -n orders-prod get scaledobject,hpa
   ```

4. **Upstream or network.** Check Envoy Gateway's own errors (5xx produced by
   the gateway rather than the app) and recent NetworkPolicy changes.
5. **Traces.** In Grafana → Explore → Tempo, filter on
   `service.name="orders-api"` with status error to see where time or errors
   come from.

## Mitigation

Make it stop first, then find the cause.

- **Bad release, rollout in progress:**
  `kubectl argo rollouts abort orders-api -n orders-prod`. Stable keeps
  serving.
- **Bad release, already fully promoted:** revert the image-tag commit in
  `values-prod.yaml` (`git revert <sha>`), merge, then sync `orders-api-prod`
  in Argo CD. The canary runs the old version back in. For speed during an
  incident, `kubectl argo rollouts undo orders-api -n orders-prod`, then
  revert in Git so Argo CD doesn't reapply the bad version.
- **Saturation:** raise `autoscaling.maxReplicas` in `values-prod.yaml`
  through a PR. If Karpenter can't add nodes, see
  [node not ready](node-not-ready.md).
- **Single bad pod:** `kubectl -n orders-prod delete pod <name>`. The ReplicaSet
  replaces it, and the PDB protects capacity.

## Escalation

- Page still firing 30 minutes after mitigation, or more than 20% of the
  monthly budget spent: escalate to the team-orders lead and post in
  `#incident`.
- Dependency outage (cloud provider, database): open a provider support case,
  and link the provider status page in the incident channel.
- After resolution, write a blameless post-incident review within 5 working
  days. If the canary analysis should have caught it, add the missing signal to
  the `AnalysisTemplate`.

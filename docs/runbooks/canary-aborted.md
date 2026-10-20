# Runbook: canary aborted

## Symptoms

- Argo CD shows `orders-api-<env>` as **Degraded**, with the message
  `RolloutAborted: Rollout aborted update to revision N`.
- The Argo Rollouts dashboard shows the rollout stopped at an analysis step,
  with the analysis marked Failed.
- Users are not affected. Aborting scales the canary to zero and the stable
  ReplicaSet serves all traffic. This is the platform working as intended.

## Dashboards and queries

- Argo Rollouts dashboard (`kubectl -n argo-rollouts port-forward svc/argo-rollouts-dashboard 3100:3100`).
- Grafana → **orders-api SLO** → "Error ratio: canary vs stable" for the time
  of the rollout.

```promql
# What the analysis saw: success rate of the canary's pods only
sum(rate(http_requests_total{namespace="orders-dev", service="orders-api", rollouts_pod_template_hash="<hash>", status!~"5.."}[1m]))
  / sum(rate(http_requests_total{namespace="orders-dev", service="orders-api", rollouts_pod_template_hash="<hash>"}[1m]))
```

## Diagnosis

1. **Which metric failed, with what values?**

   ```bash
   kubectl -n orders-dev get analysisrun --sort-by=.metadata.creationTimestamp
   kubectl -n orders-dev get analysisrun <name> -o jsonpath='{range .status.metricResults[*]}{.name}{": "}{.phase}{" "}{range .measurements[*]}{.value}{" "}{end}{"\n"}{end}'
   ```

   - **`success-rate` failed:** the new version returns 5xx. Read the canary's
     logs before they're gone. The aborted ReplicaSet is kept, scaled to zero,
     so its pod template is still inspectable.
   - **`latency-p95` failed:** the new version is slower. Compare traces of
     canary and stable pods.
   - **Phase `Error` rather than `Failed`:** the analysis couldn't query
     Prometheus. That's an infrastructure problem, not a bad release. Check
     `kubectl -n monitoring get pods` and the address in the template.

2. **Is the failure real?** Low traffic makes ratios noisy: one 500 out of 20
   requests is 95%. Check the request rate at the time. If it was very low,
   the thresholds or `count` may need tuning for that environment.

## Mitigation

- **Real regression:** nothing urgent; stable is serving. Revert or fix the
  code. The next image CI promotes starts a new canary.
- **Clear the Degraded state without a new version:** point the Application
  back at the stable image. In Git, revert the `values-<env>.yaml` commit. On
  kind, use `make demo-reset`. Once the spec matches the stable revision, the
  Rollout returns to Healthy without a new canary.
- **False positive** (analysis `Error`, or noise at low traffic): fix the cause,
  then `kubectl argo rollouts retry rollout orders-api -n <ns>`. Never promote
  past a failed analysis with `promote --full` in prod without a second person
  agreeing.

## Escalation

- Repeated false positives: open a ticket for the platform team to tune the
  `AnalysisTemplate` (thresholds, `count`, `failureLimit`).
- Analysis `Error` because Prometheus is down: treat it as a monitoring outage
  and page the platform on-call. Deploys are effectively blocked until it's
  back.

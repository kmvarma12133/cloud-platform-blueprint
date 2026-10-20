# 0003: Argo Rollouts canary with Prometheus analysis

- Status: accepted
- Date: 2026-10-20

## Context and problem statement

A Deployment's rolling update only checks readiness. A version that answers
its probes but fails half of its real requests rolls out to 100% just as
smoothly as a good one. We want a bad version to stop itself, using the same
signals as the SLO (error rate and latency), before most users see it.

## Decision drivers

- Promotion decided by metrics, not by a person watching a dashboard.
- Measure the new version on its own, so healthy stable pods can't hide a bad
  canary.
- Works the same on EKS, AKS and kind, without requiring a service mesh.
- Visible: each step and analysis result shows up in Argo CD.

## Considered options

1. Deployment rolling update, with a human watching dashboards.
2. Argo Rollouts canary, with traffic split by replica count.
3. Argo Rollouts canary, with traffic split by a router (Gateway API, mesh).
4. Flagger.
5. Blue/green.

## Decision outcome

Option 2. `orders-api` is a `Rollout` with the steps 10% → pause 2m → 30% →
analysis → 60% → analysis → 100%. Without a traffic router, the weight is
achieved by scaling the canary and stable ReplicaSets behind one Service.

The `AnalysisTemplate` runs two Prometheus queries per measurement: success
rate (non-5xx / all) at least 99%, and p95 latency under 300ms. Both read only
the canary's pods. The ServiceMonitor copies the `rollouts-pod-template-hash`
pod label onto every series, and the analysis passes the new ReplicaSet's hash
as an argument. With four measurements 30 seconds apart and `failureLimit: 1`,
a broken canary is aborted within about a minute of reaching an analysis step.
The stable ReplicaSet never stops serving.

`make demo-rollback` exercises exactly this path. It deploys an image that
fails 50% of API calls while staying Ready.

### Consequences

Good:

- A bad release is stopped by the platform, and the evidence (measured values
  per step) is kept in the `AnalysisRun`.
- Each analysis tests only the new code, so it can't pass on the strength of
  healthy stable pods.
- No mesh or ingress integration is needed, which keeps local and multi-cloud
  behaviour identical.

Bad:

- **Weights are approximate.** With two replicas, "10%" is one canary pod out
  of three, so about 33% of requests. KEDA scaling the Rollout changes the
  ratio further.
- **A bad canary serves real traffic during the first 2-minute pause**, before
  the first analysis. Adding a background analysis from step 0, or a traffic
  router for precise small weights, would shorten that window.
- **No traffic counts as a pass.** If the canary receives no requests, the
  query returns no data or 0/0, and both are treated as passing. Otherwise an
  idle environment could never promote. The rollback demo always runs under
  load for this reason.
- **Tools that expect a Deployment need adapting.** The KEDA `ScaledObject`
  targets the Rollout, and `spec.replicas` is omitted so Argo CD and the HPA
  don't fight.

## Pros and cons of the other options

**Rolling update with a human.** No new CRD, but it depends on someone noticing
in time. It also measures a mixed population of old and new pods.

**Traffic-router canary.** Precise weights (1%, 5%) and header-based testing,
via Envoy Gateway or a mesh. This is the natural next step now that the
platform runs Gateway API (see ADR 0008). It isn't the default because it ties
the rollout to the gateway on each cluster.

**Flagger.** Comparable analysis model, but it needs a mesh or ingress
integration to shift traffic, and it lacks Argo CD's per-step UI.

**Blue/green.** A clean cut-over and an instant rollback, but the new version
gets 0% and then 100% of traffic, with no measured exposure in between, and it
needs twice the capacity during the switch.

# Runbook: Argo CD application OutOfSync or not syncing

## Symptoms

- An Application shows **OutOfSync** in the UI or in
  `kubectl -n argocd get applications`, or **Synced** but Degraded or Missing.
- A merged change hasn't appeared in the cluster.
- The `ArgoAppNotSynced` alert, if Argo CD's metrics are scraped.

In prod, OutOfSync after a merge is expected: prod Applications have no
automated sync, so a person syncs them after reviewing the diff. This runbook
is for OutOfSync that shouldn't be there.

## Dashboards and queries

```bash
kubectl -n argocd get applications -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision
kubectl -n argocd get application <app> -o jsonpath='{.status.conditions}'
kubectl -n argocd get application <app> -o jsonpath='{.status.operationState.message}'
```

In the UI, open the app and use **App diff**. It shows exactly which fields
differ between Git and the live state.

## Diagnosis

1. **Git or render error** (`ComparisonError` condition). The manifests don't
   render: a bad values key, a missing file, or an unreachable chart repo.
   Reproduce locally with `make k8s-validate` and `make k8s-validate-addons`,
   which render exactly what Argo CD renders.
2. **Something changed the live object.** In dev, `selfHeal` reverts it within
   minutes. Look at who did it: `kubectl get events`, and audit logs on EKS
   (CloudWatch, `/aws/eks/<cluster>/cluster`).
3. **A controller legitimately mutates a field.** Typical cases are
   `spec.replicas` set by an HPA or KEDA, webhook-injected defaults, or a CRD's
   `caBundle`. That's a permanent diff, so add an `ignoreDifferences` entry for
   that field to the Application rather than fighting the controller. The
   orders-api chart avoids this for replicas by omitting `spec.replicas` when
   KEDA is on.
4. **Sync fails.** The `operationState.message` says why:
   - `the server could not find the requested resource`: a CRD isn't installed
     yet. Check sync waves, and whether the CRD's Application is healthy.
   - `admission webhook ... denied the request`: a Gatekeeper constraint in
     prod (`deny`) rejected the change. The message names the constraint; fix
     the manifest.
   - `metadata.annotations: Too long`: the CRD needs `ServerSideApply=true`.
5. **Waiting on a sync wave.** A child Application in a later wave stays
   OutOfSync until earlier waves are Healthy. Find the unhealthy one first.

## Mitigation

- Fix the manifest in Git. That is almost always the right fix.
- Force a refresh after fixing a transient repo or network error:
  `kubectl -n argocd annotate application <app> argocd.argoproj.io/refresh=hard --overwrite`.
- Emergency manual change in prod: make it, then put the same change in Git
  immediately. Otherwise the next sync reverts it. Note the incident.
- Stuck operation: `kubectl -n argocd patch application <app> --type merge -p '{"operation":null}'`,
  then sync again.

## Escalation

- Argo CD itself is unhealthy (repo-server or application-controller
  crashing): page the platform on-call. Workloads keep running, but no
  changes, including rollbacks through Git, can be delivered until it's fixed.
- A Gatekeeper denial blocking an urgent fix in prod: the change author and the
  platform on-call decide together. Prefer fixing the manifest over removing
  the constraint.

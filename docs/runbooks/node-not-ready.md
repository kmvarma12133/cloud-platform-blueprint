# Runbook: node NotReady, or Karpenter not provisioning

## Symptoms

- `KubeNodeNotReady` or `KubeNodeUnreachable` alerts (kube-prometheus-stack).
- Pods stuck in `Pending` with events such as `0/5 nodes are available`, or
  `FailedScheduling` and no new node appearing.
- Karpenter NodeClaims stuck before `Ready`, or being launched and deleted in
  a loop.

## Dashboards and queries

- Grafana → **Kubernetes / Compute Resources / Cluster** and
  **Node Exporter / Nodes** (shipped with kube-prometheus-stack).
- Karpenter's own metrics are scraped through its ServiceMonitor:

```promql
# Pods Karpenter is trying to place
sum(karpenter_pods_state{phase="Pending"})
# Launch failures by reason over the last hour
sum by (reason) (increase(karpenter_nodeclaims_terminated_total[1h]))
# Is the NodePool at its CPU limit?
karpenter_nodepools_usage{resource_type="cpu"} / karpenter_nodepools_limit{resource_type="cpu"}
```

## Diagnosis

1. **Is it one node, or capacity in general?**

   ```bash
   kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type,topology.kubernetes.io/zone
   kubectl get nodeclaims -o wide
   kubectl get pods -A --field-selector=status.phase=Pending
   ```

2. **Single NotReady node.**

   ```bash
   kubectl describe node <node>   # Conditions: MemoryPressure, DiskPressure, PIDPressure, NetworkUnavailable
   ```

   - If it's a spot node, check whether an interruption was received:
     `kubectl -n karpenter logs deploy/karpenter | grep -i interrupt`.
     Karpenter normally drains such nodes ahead of time.
   - For Bottlerocket nodes, use the admin container through SSM. There is no
     SSH by design.

3. **Karpenter isn't launching anything.**

   ```bash
   kubectl -n karpenter logs deploy/karpenter --since=30m | grep -E 'ERROR|could not|insufficient'
   kubectl describe nodepool default        # limits reached? (status.resources vs spec.limits)
   kubectl describe ec2nodeclass default    # status conditions: subnets, SGs, AMI, instance profile resolved?
   ```

   Common causes, in order:

   1. **NodePool `limits` reached.** This is a deliberate cost ceiling, not a
      fault.
   2. **The pod's requirements match no allowed instance type.** Look for
      nodeSelectors, an arch other than amd64, or a request larger than any
      c/m/r instance.
   3. **Subnet or security group discovery found nothing.** Check the
      `karpenter.sh/discovery` tags that Terraform sets on the private subnets
      and the cluster security group.
   4. **IAM.** `UnauthorizedOperation` in the logs means the controller policy
      in `infra/modules/aws-eks/karpenter.tf` no longer matches what Karpenter
      calls. This usually happens after a Karpenter upgrade.
   5. **No spot capacity and on-demand also exhausted** in that AZ. Rare; the
      wide instance list exists to prevent it.

4. **Karpenter itself is down.** It runs on the managed system node group.
   Check `kubectl -n karpenter get pods` and the health of that node group in
   the EKS console.

## Mitigation

- **A NotReady node that doesn't recover in about 10 minutes:** delete its
  NodeClaim (`kubectl delete nodeclaim <name>`). Karpenter drains it,
  respecting PDBs, and replaces it.
- **Limit reached and the demand is legitimate:** raise `spec.limits` in
  `platform/karpenter/overlays/<env>` through a PR.
- **Discovery or IAM problem:** fix it in Terraform and apply. As a stopgap,
  scale the system node group's `max_size` if critical pods are pending.
- **Karpenter down:** scale the system node group up, and check its pods for
  OOM and the Pod Identity association.

## Escalation

- Capacity unavailable in multiple AZs: open an AWS support case, which counts
  as a "production system impaired" severity for prod.
- Persistent IAM or API errors after an upgrade: roll Karpenter back to the
  previous chart version in Git, then open a ticket for the platform team.

# 0004: Karpenter instead of Cluster Autoscaler on EKS

- Status: accepted
- Date: 2026-10-20

## Context and problem statement

EKS worker capacity has to follow demand, use spot where possible, and not
waste half-empty nodes. Cluster Autoscaler scales Auto Scaling Groups, each
with a fixed instance-type list. Covering many instance types and both
capacity types means many node groups, and the autoscaler can only grow the
group it guesses will fit.

## Decision drivers

- Spot by default, with on-demand fallback and graceful handling of
  interruptions.
- Choose from a wide range of instance shapes. More spot pools mean fewer
  interruptions and better prices.
- Scale-up in seconds rather than minutes, and active bin-packing on the way
  down.
- Nodes replaced regularly, so AMI updates roll out without a manual drain.

## Considered options

1. Cluster Autoscaler with managed node groups.
2. Karpenter, with a small managed node group for itself.
3. EKS Auto Mode.
4. Fargate.

## Decision outcome

Option 2. Karpenter runs on a small on-demand Bottlerocket node group tainted
`CriticalAddonsOnly`, so it never schedules onto capacity it manages itself.
Application pods land on Karpenter nodes defined by one NodePool and one
EC2NodeClass in `platform/karpenter`:

- spot and on-demand across the c, m and r families, generation 6 and newer;
- `WhenEmptyOrUnderutilized` consolidation with a 10% disruption budget;
- `expireAfter: 720h`, so every node is replaced at least monthly;
- a per-environment CPU and memory ceiling as a cost guardrail;
- Bottlerocket pinned to a release. Bumping the pin is a Git change that
  Karpenter's drift detection turns into a rolling node replacement.

Terraform owns the AWS side in `infra/modules/aws-eks/karpenter.tf`:

- the node role and its access entry;
- the controller role through EKS Pod Identity;
- a controller policy scoped by resource ARN and ownership tags;
- the SQS interruption queue fed by EventBridge.

### Consequences

Good:

- Workloads get right-sized nodes from dozens of instance types. Spot
  interruptions arrive about two minutes early and nodes are drained
  gracefully. Empty or under-used nodes are removed.
- The cost lever is explicit, in one file per environment.

Bad:

- Karpenter is on the critical path for capacity. It runs with two replicas on
  dedicated nodes, and the managed group is sized to keep it and CoreDNS up.
- Consolidation moves pods around. Workloads need PodDisruptionBudgets and
  graceful shutdown; the orders-api chart sets `maxUnavailable: 1`.
- The image is built for amd64 only. Graviton (arm64) is usually 20% or more
  cheaper, but needs a multi-arch image build first.
- AKS keeps the cluster autoscaler on its user pool. AKS Node Auto Provisioning,
  which is Karpenter-based, would be the equivalent there.

## Pros and cons of the other options

**Cluster Autoscaler.** Mature and simple, but bound to ASGs: one instance
shape mix per group, slower scale-up, and consolidation limited to removing
whole empty nodes.

**EKS Auto Mode.** AWS runs Karpenter, the CNI, CoreDNS and storage
add-ons for you. That's a strong option for teams that don't want to operate
these, but it charges a premium on instance cost and gives up control over
versions and configuration. This repo also aims to show how the pieces fit
together.

**Fargate.** No nodes to manage, but no DaemonSets, no spot discount on EKS,
and per-pod sizing that is expensive for steady workloads.

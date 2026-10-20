# METADATA
# description: >-
#   Helpers shared by every policy. scripts/build-gatekeeper.py embeds this file
#   in each ConstraintTemplate's libs, which is why the package sits under lib.
package lib.k8s

import rego.v1

# Kinds that embed a pod template at spec.template. Checking these as well as
# Pods means a bad Deployment or Rollout is rejected when it is applied, not
# later when its ReplicaSet quietly fails to create pods.
templated_kinds := {"Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job", "Rollout"}

pod_spec(obj) := obj.spec if obj.kind == "Pod"

pod_spec(obj) := obj.spec.template.spec if obj.kind in templated_kinds

pod_spec(obj) := obj.spec.jobTemplate.spec.template.spec if obj.kind == "CronJob"

containers(obj) := array.concat(
	object.get(pod_spec(obj), "containers", []),
	object.get(pod_spec(obj), "initContainers", []),
)

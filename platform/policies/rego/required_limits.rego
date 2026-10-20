# METADATA
# title: Require CPU and memory limits
# description: >-
#   Every container must set CPU and memory limits, so a single workload cannot
#   starve its neighbours on a shared node.
# custom:
#   kind: K8sRequiredLimits
package k8srequiredlimits

import data.lib.k8s
import rego.v1

violation contains {"msg": msg} if {
	some c in k8s.containers(input.review.object)
	some resource in ["cpu", "memory"]
	not c.resources.limits[resource]
	msg := sprintf("container %q has no %s limit", [c.name, resource])
}

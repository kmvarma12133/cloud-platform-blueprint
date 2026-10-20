# METADATA
# title: Require runAsNonRoot
# description: >-
#   Every container must run as a non-root user, either through its own
#   securityContext or the pod's (a container may not override the pod back to
#   root).
# custom:
#   kind: K8sRequireNonRoot
package k8srequirenonroot

import data.lib.k8s
import rego.v1

violation contains {"msg": msg} if {
	spec := k8s.pod_spec(input.review.object)
	some c in k8s.containers(input.review.object)
	not runs_as_non_root(spec, c)
	msg := sprintf("container %q must set runAsNonRoot: true (in its own or the pod's securityContext)", [c.name])
}

runs_as_non_root(_, c) if c.securityContext.runAsNonRoot == true

runs_as_non_root(spec, c) if {
	spec.securityContext.runAsNonRoot == true
	not c.securityContext.runAsNonRoot == false
}

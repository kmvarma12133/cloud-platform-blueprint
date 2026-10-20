# METADATA
# title: Require ownership labels
# description: >-
#   Workloads and pods must carry the listed labels (app.kubernetes.io/name and
#   owner by default), so every running thing can be traced to a service and a
#   team for cost allocation and incident routing.
# custom:
#   kind: K8sRequiredLabels
#   parameters:
#     labels:
#       type: array
#       description: Label keys that must be present.
#       items:
#         type: string
package k8srequiredlabels

import rego.v1

violation contains {"msg": msg} if {
	obj := input.review.object
	provided := object.keys(object.get(obj.metadata, "labels", {}))
	some required in input.parameters.labels
	not required in provided
	name := object.get(obj.metadata, "name", object.get(obj.metadata, "generateName", ""))
	msg := sprintf("%s %q is missing required label %q", [obj.kind, name, required])
}

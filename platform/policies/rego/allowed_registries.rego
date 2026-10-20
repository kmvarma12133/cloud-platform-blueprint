# METADATA
# title: Allow images only from approved registries
# description: >-
#   Every image must match one of the configured registry patterns (anchored
#   regular expressions), e.g. the organisation's ECR, ACR and GHCR namespaces.
# custom:
#   kind: K8sAllowedRegistries
#   parameters:
#     registries:
#       type: array
#       description: Regular expressions; an image is allowed if any one matches.
#       items:
#         type: string
package k8sallowedregistries

import data.lib.k8s
import rego.v1

violation contains {"msg": msg} if {
	some c in k8s.containers(input.review.object)
	not allowed(c.image)
	msg := sprintf("container %q image %q is not from an approved registry", [c.name, c.image])
}

allowed(image) if {
	some pattern in input.parameters.registries
	regex.match(pattern, image)
}

# METADATA
# title: Disallow the latest tag and untagged images
# description: >-
#   Images must be pinned to a tag other than latest, or to a digest, so that
#   what runs is what was scanned, signed and reviewed.
# custom:
#   kind: K8sDisallowLatestTag
package k8sdisallowlatesttag

import data.lib.k8s
import rego.v1

violation contains {"msg": msg} if {
	some c in k8s.containers(input.review.object)
	not pinned(c.image)
	msg := sprintf("container %q uses %q: pin a version tag or a digest, not latest or no tag", [c.name, c.image])
}

pinned(image) if contains(image, "@sha256:")

pinned(image) if {
	not contains(image, "@")
	image_tag(image) != "latest"
}

# The tag follows the last ":" in the final path segment, so a registry port
# (registry.local:5000/app) is not mistaken for a tag.
image_tag(image) := tag if {
	segments := split(image, "/")
	name := segments[count(segments) - 1]
	contains(name, ":")
	tag := split(name, ":")[1]
}

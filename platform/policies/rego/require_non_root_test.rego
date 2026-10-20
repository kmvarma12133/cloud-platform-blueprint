package k8srequirenonroot

import rego.v1

pod(pod_sc, container_sc) := {"review": {"object": {"kind": "Pod", "metadata": {"name": "p"}, "spec": {
	"securityContext": pod_sc,
	"containers": [{"name": "app", "image": "x:1", "securityContext": container_sc}],
}}}}

test_pod_level_non_root_is_allowed if {
	count(violation) == 0 with input as pod({"runAsNonRoot": true}, {})
}

test_container_level_non_root_is_allowed if {
	count(violation) == 0 with input as pod({}, {"runAsNonRoot": true})
}

test_unset_is_denied if {
	count(violation) == 1 with input as pod({}, {})
}

test_container_cannot_override_pod_to_root if {
	count(violation) == 1 with input as pod({"runAsNonRoot": true}, {"runAsNonRoot": false})
}

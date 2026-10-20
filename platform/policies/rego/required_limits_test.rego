package k8srequiredlimits

import rego.v1

pod(resources) := {"review": {"object": {
	"kind": "Pod",
	"metadata": {"name": "p"},
	"spec": {"containers": [{"name": "app", "image": "x:1", "resources": resources}]},
}}}

test_limits_set_is_allowed if {
	count(violation) == 0 with input as pod({"limits": {"cpu": "500m", "memory": "256Mi"}})
}

test_missing_memory_limit_is_denied if {
	violation == {{"msg": "container \"app\" has no memory limit"}} with input as pod({"limits": {"cpu": "500m"}})
}

test_requests_alone_are_not_enough if {
	count(violation) == 2 with input as pod({"requests": {"cpu": "100m", "memory": "64Mi"}})
}

test_init_containers_are_checked if {
	inp := {"review": {"object": {"kind": "Deployment", "metadata": {"name": "d"}, "spec": {"template": {"spec": {
		"containers": [{"name": "app", "resources": {"limits": {"cpu": "1", "memory": "1Gi"}}}],
		"initContainers": [{"name": "migrate"}],
	}}}}}}
	count(violation) == 2 with input as inp
}

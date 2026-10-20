package k8sallowedregistries

import rego.v1

registries := [
	`^[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/`,
	`^[a-z0-9]+\.azurecr\.io/`,
	`^ghcr\.io/acme/`,
]

pod(image) := {
	"parameters": {"registries": registries},
	"review": {"object": {"kind": "Pod", "metadata": {"name": "p"}, "spec": {"containers": [{"name": "app", "image": image}]}}},
}

test_ecr_is_allowed if {
	count(violation) == 0 with input as pod("123456789012.dkr.ecr.eu-west-1.amazonaws.com/orders-api:1.0.0")
}

test_acr_is_allowed if {
	count(violation) == 0 with input as pod("cpbregistry.azurecr.io/orders-api:1.0.0")
}

test_own_ghcr_namespace_is_allowed if {
	count(violation) == 0 with input as pod("ghcr.io/acme/orders-api:1.0.0")
}

test_other_ghcr_namespace_is_denied if {
	count(violation) == 1 with input as pod("ghcr.io/someone-else/orders-api:1.0.0")
}

test_docker_hub_is_denied if {
	count(violation) == 1 with input as pod("nginx:1.27")
}

test_lookalike_host_is_denied if {
	# Anchored patterns stop "ghcr.io.evil.example/..." from matching.
	count(violation) == 1 with input as pod("ghcr.io.evil.example/acme/orders-api:1.0.0")
}

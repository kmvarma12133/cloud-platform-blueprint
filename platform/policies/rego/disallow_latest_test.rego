package k8sdisallowlatesttag

import rego.v1

pod(image) := {"review": {"object": {"kind": "Pod", "metadata": {"name": "p"}, "spec": {"containers": [{"name": "app", "image": image}]}}}}

test_version_tag_is_allowed if {
	count(violation) == 0 with input as pod("ghcr.io/acme/orders-api:3f2c1a9")
}

test_digest_is_allowed if {
	count(violation) == 0 with input as pod("ghcr.io/acme/orders-api@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
}

test_latest_is_denied if {
	count(violation) == 1 with input as pod("ghcr.io/acme/orders-api:latest")
}

test_untagged_is_denied if {
	count(violation) == 1 with input as pod("nginx")
}

test_registry_port_is_not_a_tag if {
	count(violation) == 1 with input as pod("registry.local:5000/orders-api")
}

test_registry_port_with_tag_is_allowed if {
	count(violation) == 0 with input as pod("registry.local:5000/orders-api:1.2.3")
}

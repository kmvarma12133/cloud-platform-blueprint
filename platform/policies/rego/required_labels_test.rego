package k8srequiredlabels

import rego.v1

obj(labels) := {
	"parameters": {"labels": ["app.kubernetes.io/name", "owner"]},
	"review": {"object": {"kind": "Deployment", "metadata": {"name": "orders-api", "labels": labels}}},
}

test_all_labels_present_is_allowed if {
	count(violation) == 0 with input as obj({"app.kubernetes.io/name": "orders-api", "owner": "team-orders", "extra": "x"})
}

test_missing_owner_is_denied if {
	violation == {{"msg": "Deployment \"orders-api\" is missing required label \"owner\""}} with input as obj({"app.kubernetes.io/name": "orders-api"})
}

test_no_labels_reports_each_missing_label if {
	count(violation) == 2 with input as {
		"parameters": {"labels": ["app.kubernetes.io/name", "owner"]},
		"review": {"object": {"kind": "Pod", "metadata": {"generateName": "orders-api-"}}},
	}
}

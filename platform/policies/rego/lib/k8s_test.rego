package lib.k8s_test

import data.lib.k8s
import rego.v1

test_pod_containers_include_init_containers if {
	pod := {"kind": "Pod", "spec": {"containers": [{"name": "app"}], "initContainers": [{"name": "init"}]}}
	[c.name | some c in k8s.containers(pod)] == ["app", "init"]
}

test_rollout_uses_pod_template if {
	rollout := {"kind": "Rollout", "spec": {"template": {"spec": {"containers": [{"name": "app"}]}}}}
	count(k8s.containers(rollout)) == 1
}

test_cronjob_uses_job_template if {
	cj := {"kind": "CronJob", "spec": {"jobTemplate": {"spec": {"template": {"spec": {"containers": [{"name": "c"}]}}}}}}
	count(k8s.containers(cj)) == 1
}

test_unrelated_kind_has_no_containers if {
	not k8s.containers({"kind": "ConfigMap", "data": {}})
}

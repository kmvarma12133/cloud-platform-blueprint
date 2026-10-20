#!/usr/bin/env python3
"""Render every Helm-based Argo CD Application exactly as Argo CD would, and validate it.

For each cluster directory under platform/gitops/clusters, the Applications are
built with kustomize. Every chart source is then rendered with `helm template`
at its pinned version, using the same value files ($values/... resolved to this
checkout) and inline valuesObject, and the output is checked with kubeconform.
This catches chart upgrades or value typos that only show up at sync time.

    python scripts/render-addons.py            # all clusters
    python scripts/render-addons.py local      # one cluster
"""

from __future__ import annotations

import hashlib
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
CLUSTERS = ROOT / "platform" / "gitops" / "clusters"
WORK = ROOT / ".cache" / "render-addons"
# Overridable so the script also works where a tool is a wrapper script.
HELM = shlex.split(os.environ.get("HELM", "helm"))
KUBECTL = shlex.split(os.environ.get("KUBECTL", "kubectl"))
KUBECONFORM = shlex.split(os.environ.get("KUBECONFORM", "kubeconform"))
CRDS_CATALOG = (
    "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/"
    "{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
)


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    # Commands run from the repo root so value-file paths are relative to it.
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kwargs)  # noqa: S603


def applications(cluster: Path) -> list[dict]:
    built = run([*KUBECTL, "kustomize", str(cluster.relative_to(ROOT).as_posix())])
    if built.returncode != 0:
        sys.exit(f"kustomize failed for {cluster.name}:\n{built.stderr}")
    docs = [d for d in yaml.safe_load_all(built.stdout) if d]
    return [d for d in docs if d["kind"] == "Application"]


def helm_command(app: dict, source: dict) -> list[str] | None:
    if "chart" not in source and not source["repoURL"].startswith("oci://"):
        return None  # a Git path, not a chart
    name = app["metadata"]["name"]
    helm = source.get("helm", {})
    namespace = app["spec"]["destination"]["namespace"]
    if source["repoURL"].startswith("oci://"):
        ref = source["repoURL"] + (f"/{source['chart']}" if "chart" in source else "")
        cmd = [*HELM, "template", helm.get("releaseName", name), ref]
    else:
        cmd = [*HELM, "template", helm.get("releaseName", name), source["chart"]]
        cmd += ["--repo", source["repoURL"]]
    cmd += ["--version", str(source["targetRevision"]), "--namespace", namespace]
    for vf in helm.get("valueFiles", []):
        cmd += ["--values", vf.replace("$values/", "")]
    if helm.get("valuesObject"):
        body = json.dumps(helm["valuesObject"], sort_keys=True)
        path = WORK / f"{name}-{hashlib.sha256(body.encode()).hexdigest()[:10]}.json"
        path.write_text(body)
        cmd += ["--values", path.relative_to(ROOT).as_posix()]
    return cmd


def main() -> int:
    WORK.mkdir(parents=True, exist_ok=True)
    wanted = set(sys.argv[1:])
    clusters = [c for c in sorted(CLUSTERS.iterdir()) if c.is_dir()]
    clusters = [c for c in clusters if not wanted or c.name in wanted]

    seen: dict[str, str] = {}
    failures = 0
    for cluster in clusters:
        for app in applications(cluster):
            sources = app["spec"].get("sources") or [app["spec"]["source"]]
            for source in sources:
                cmd = helm_command(app, source)
                if cmd is None:
                    continue
                key = " ".join(cmd)
                label = f"{cluster.name}/{app['metadata']['name']}"
                if key in seen:
                    print(f"{label:45} same as {seen[key]}")
                    continue
                seen[key] = label
                rendered = run(cmd)
                if rendered.returncode != 0:
                    print(f"{label:45} helm template FAILED\n{rendered.stderr}")
                    failures += 1
                    continue
                checked = run(
                    [
                        *KUBECONFORM,
                        "-strict",
                        "-summary",
                        "-schema-location",
                        "default",
                        "-schema-location",
                        CRDS_CATALOG,
                        "-",
                    ],
                    input=rendered.stdout,
                )
                status = checked.stdout.strip().splitlines()[-1] if checked.stdout else ""
                print(f"{label:45} {status.replace('Summary: ', '')}")
                if checked.returncode != 0:
                    print(checked.stdout)
                    failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

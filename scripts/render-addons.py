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
import time
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
# Anonymous pulls from public OCI registries (ECR Public in particular) are rate
# limited per source IP, and shared CI runners hit that regularly.
RATE_LIMITED = ("429", "toomanyrequests")
PULL_ATTEMPTS = 4


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    # Commands run from the repo root so value-file paths are relative to it.
    return subprocess.run(  # noqa: S603
        cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", **kwargs
    )


def applications(cluster: Path) -> list[dict]:
    built = run([*KUBECTL, "kustomize", str(cluster.relative_to(ROOT).as_posix())])
    if built.returncode != 0:
        sys.exit(f"kustomize failed for {cluster.name}:\n{built.stderr}")
    docs = [d for d in yaml.safe_load_all(built.stdout) if d]
    return [d for d in docs if d["kind"] == "Application"]


def oci_ref(source: dict) -> str | None:
    if not source["repoURL"].startswith("oci://"):
        return None
    return source["repoURL"] + (f"/{source['chart']}" if "chart" in source else "")


def pull_oci(ref: str, version: str) -> tuple[str | None, str]:
    """Pull an OCI chart once into the cache, retrying registry rate limits.

    Returns the chart archive path relative to the repo root, or None and the
    last helm error.
    """
    dest = WORK / "charts" / hashlib.sha256(f"{ref}:{version}".encode()).hexdigest()[:10]
    if cached := sorted(dest.glob("*.tgz")):
        return cached[0].relative_to(ROOT).as_posix(), ""
    dest.mkdir(parents=True, exist_ok=True)
    for attempt in range(PULL_ATTEMPTS):
        pulled = run(
            [*HELM, "pull", ref, "--version", version, "--destination", dest.relative_to(ROOT)]
        )
        if pulled.returncode == 0:
            return sorted(dest.glob("*.tgz"))[0].relative_to(ROOT).as_posix(), ""
        if not any(s in pulled.stderr for s in RATE_LIMITED) or attempt == PULL_ATTEMPTS - 1:
            return None, pulled.stderr
        time.sleep(15 * 2**attempt)
    raise AssertionError("unreachable")


def helm_command(app: dict, source: dict, chart_path: str | None = None) -> list[str] | None:
    if "chart" not in source and not source["repoURL"].startswith("oci://"):
        return None  # a Git path, not a chart
    name = app["metadata"]["name"]
    helm = source.get("helm", {})
    namespace = app["spec"]["destination"]["namespace"]
    if chart_path:
        # Already pulled at the pinned version (see pull_oci).
        cmd = [*HELM, "template", helm.get("releaseName", name), chart_path]
    else:
        cmd = [*HELM, "template", helm.get("releaseName", name), source["chart"]]
        cmd += ["--repo", source["repoURL"], "--version", str(source["targetRevision"])]
    cmd += ["--namespace", namespace]
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
                label = f"{cluster.name}/{app['metadata']['name']}"
                chart_path = None
                if ref := oci_ref(source):
                    chart_path, error = pull_oci(ref, str(source["targetRevision"]))
                    if chart_path is None:
                        if any(s in error for s in RATE_LIMITED):
                            # The registry refused us, not the chart: report it
                            # visibly without failing the build.
                            print(f"::warning::{label}: not rendered, {ref} is rate limited")
                        else:
                            print(f"{label:45} helm pull FAILED\n{error}")
                            failures += 1
                        continue
                cmd = helm_command(app, source, chart_path)
                if cmd is None:
                    continue
                key = " ".join(cmd)
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
                        # CRD definitions are upstream artifacts that the API
                        # server validates on apply; every custom resource
                        # instance is still checked against the catalog.
                        "-skip",
                        "CustomResourceDefinition",
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

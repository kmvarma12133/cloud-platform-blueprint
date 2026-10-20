#!/usr/bin/env bash
# Lint and unit-test the PrometheusRule manifests with promtool.
#
# promtool reads plain rule files, so the rule groups are first extracted from
# each PrometheusRule's .spec into a scratch directory next to copies of the
# tests in platform/observability/rules/tests.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RULES_DIR="$ROOT/platform/observability/rules"
WORK="$ROOT/.cache/promtool"
PROMTOOL="${PROMTOOL:-promtool}"
PYTHON="${PYTHON:-python3}"

rm -rf "$WORK" && mkdir -p "$WORK"

"$PYTHON" - "$RULES_DIR" "$WORK" <<'PY'
import pathlib, sys, yaml
src, out = map(pathlib.Path, sys.argv[1:])
for f in sorted(src.glob("*.yaml")):
    doc = yaml.safe_load(f.read_text())
    if doc.get("kind") == "PrometheusRule":
        (out / f"{f.stem}.rules.yaml").write_text(yaml.safe_dump(doc["spec"], sort_keys=False))
PY
cp "$RULES_DIR"/tests/*.yaml "$WORK"/

cd "$WORK"
"$PROMTOOL" check rules ./*.rules.yaml
"$PROMTOOL" test rules ./*.test.yaml

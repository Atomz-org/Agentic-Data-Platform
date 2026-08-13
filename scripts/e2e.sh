#!/usr/bin/env bash
#
# End-to-end semantic pipeline across the two platform submodules:
#
#   code-skills   dbt build → MetricFlow definitions compiled per serving tier
#                 (wren MDL views, lightdash meta, the Evidence query bundle)
#   evidence-bi   pulls the built DuckDB + compiled bundle, builds the dashboards
#
# One definition, every tier; the equivalence gate holds the compile to it.
# Idempotent: toolchains bootstrap only when missing. Roughly 4 minutes cold,
# under 1 minute warm.
#
#   ./scripts/e2e.sh              # full chain
#   SKIP_BOOTSTRAP=1 ./scripts/e2e.sh   # toolchains already present

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CS="$ROOT/code-skills"
EB="$ROOT/evidence-bi"
UC="${UC:-example-order-revenue-mart}"

step() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

if [ ! -f "$CS/README.md" ] || [ ! -f "$EB/package.json" ]; then
    echo "Submodules not initialised — run: git submodule update --init" >&2
    exit 2
fi

if [ "${SKIP_BOOTSTRAP:-0}" != "1" ]; then
    step "Toolchain bootstrap (idempotent)"
    if [ ! -x "$CS/.venv/bin/python" ]; then
        if command -v uv >/dev/null 2>&1; then
            (cd "$CS" && uv venv --seed --python 3.12 .venv)
        else
            python3 -m venv "$CS/.venv"
        fi
    fi
    "$CS/.venv/bin/pip" install -q -r "$CS/.github/requirements/ci.txt"
    "$CS/.venv/bin/pip" install -q 'dbt-core~=1.9.0' 'dbt-duckdb~=1.9.0' duckdb
    if [ ! -d "$EB/node_modules" ]; then
        (cd "$EB" && npm install)
    fi
    # Evidence's documented sqlite3 quirk: fetch the native binding if absent.
    if ! node -e "require('$EB/node_modules/sqlite3')" >/dev/null 2>&1; then
        (cd "$EB/node_modules/sqlite3" && npm run install)
    fi
fi

step "1/4 Warehouse: dbt build ($UC)"
(cd "$CS/skill-packs/dbt-skills/use-cases/$UC/dbt_project" && ./run_local.sh)

step "2/4 Semantic compile: evidence stage (wren/lightdash run too when their CLIs exist)"
(cd "$CS" && .venv/bin/python scripts/use_case_sync.py --use-case "$UC" --stage evidence)

step "3/4 Equivalence gate: compiled queries == definitions"
(cd "$CS" && .venv/bin/python -m pytest tests/test_evidence_semantic_equivalence.py -q)

step "4/4 BI: pull bundle + build dashboards"
(cd "$EB" && ./scripts/sync-dbt.sh)
(cd "$EB" && npm run build)

step "E2E complete"
echo "warehouse → compiled metrics → equivalence-gated → dashboards in $EB/build/"
echo "Preview: (cd evidence-bi && npm run preview)   Dev: (cd evidence-bi && npm run dev)"

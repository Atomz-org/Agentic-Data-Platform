# The combined platform: code-skills × evidence-bi

This repository is the umbrella for two platform submodules and the bridge between
them. Together they are one governed pipeline: metrics defined once in dbt's semantic
layer, compiled per serving tier, rendered as dashboards — with equivalence gates
holding every tier to the same numbers.

| Submodule | Role | Repository |
|---|---|---|
| `code-skills/` | Data platform: dbt method, ontology, MetricFlow semantic layer, serving-tier compilers (WrenAI, Lightdash, Evidence, OpenMetadata) | [Atomz-org/claude-copilot-skills](https://github.com/Atomz-org/claude-copilot-skills) |
| `evidence-bi/` | BI platform: Evidence.dev dashboards over the compiled semantic layer | [Atomz-org/Evidence-BI](https://github.com/Atomz-org/Evidence-BI) |

The sibling layout is load-bearing: `evidence-bi/scripts/sync-dbt.sh` defaults to
`../code-skills/...`, which is exactly where the submodule sits. Both repos work as
independent clones in the same parent directory too — the umbrella adds pinning.

## Run it

```bash
git submodule update --init
./scripts/e2e.sh
```

Four steps, each independently runnable:

```
1  dbt build            code-skills/skill-packs/dbt-skills/use-cases/<uc>/dbt_project
                        → marts + time spine in dev.duckdb, manifest + catalog in target/
2  semantic compile     use_case_sync.py --stage evidence
                        → evidence_context_sync.py compiles every MetricFlow metric and
                          saved query through the SAME resolver as the Wren MDL views,
                          at the cuts <uc>/evidence.yml declares
                        → committed bundle at <uc>/evidence/ (queries + source adapter)
3  equivalence gate     tests/test_evidence_semantic_equivalence.py
                        → every compiled query row-for-row against a hand-written oracle
                          restating its definition; the wren gate pins the MDL views to
                          the same definitions, so the tiers agree by transitivity
4  BI pull + build      evidence-bi/scripts/sync-dbt.sh  (DuckDB + bundle, re-extract)
                        npm run build                    (fails on any broken query)
```

## The BI surface

`evidence-bi` serves far more than the executive dashboard (this includes the
`feat/dynamic-report-and-notebook` and `feat/rill-explore` work — PRs #3 and #4
in that repo):

| Route | What it is |
|---|---|
| `/` | Revenue Overview — executive dashboard |
| `/showcase` | Feature Tour — ten chapters over the same governed data |
| `/canvas` | one board uniting dbt, Rill, flint-chart, Cube-style pivot, and a notebook cell (`canvas/executive.yaml`) |
| `/rill` | a Rill metrics view + explore dashboard, defined in Rill's own YAML (`rill/`) and compiled for the browser — no Rill server needed; `npm run rill:up` runs the real Rill on :9009 to check parity |
| `/flint` | the flint-chart catalog driven by the governed weekly cut |
| `/reports/revenue-performance` | print-ready management report; every exhibit opens as **Live SQL** |
| `/noodle` | drag-and-drop exploration workbench over the parquet tables |
| `/noodle-cube` | the same surface driven by the **Cube semantic layer** — measures arrive already defined, the shelf cannot redefine them (dev: set `VITE_CUBE_API_URL=http://localhost:4000` in `.env`; deployed it proxies `/cubejs-api`) |
| `/notebooks/order-anomalies` | Jupyter notebook rendered as a page (vendored Evidence patch), with the anomaly screen re-expressed live in DuckDB |
| `/studio` | build dashboards at runtime, publish back as code |
| `/gallery` | the component and layout system on real data |
| `/metrics`, `/regions/*` | metric dictionary + drill-downs |

`deploy/` (from PR #4) is a complete low-footprint VPS stack — Caddy/nginx,
systemd units, zram, low-memory ClickHouse/Postgres configs — for serving the
whole thing on a 2 GB server.

Two pieces need one-time setup beyond `e2e.sh`:

- **Notebook pages** require the vendored Evidence fork:
  `cd evidence-bi && git submodule update --init --depth 1 vendor/evidence`
  (npm's postinstall then patches `@evidence-dev/evidence` with the
  notebook→page compiler; `e2e.sh`'s npm install re-applies it).
- **The Cube tier** runs as a container over the project's own extracted
  parquet: `cd evidence-bi && npm run cube:up` (docker, or podman compose).
  Its `orders.revenue` measure is deliberately unfiltered with a
  `not_cancelled` segment as the documented governed figure — verified equal
  to the dbt definition (277,183.41 on the example data). Compiling Cube
  models from MetricFlow (a `cube` sync stage beside `wren` and `evidence`)
  is the natural next step; today the models are hand-authored and
  drift-aware by construction.

The Rill definitions follow the same discipline as everything else here: one
YAML (`rill/metrics/orders_metrics.yaml`) is read by the real Rill *and*
compiled by `scripts/build-rill-model.mjs` into the browser module the pages
render — `rill/up.sh` refuses to start if the two have drifted.

## Why the tiers cannot drift

The first generation of Evidence queries was hand-compiled from `_metrics.yml` —
careful, commented, reviewed — and three of eight still drifted (a cancellation filter
the definition doesn't declare on both cumulative metrics; a fraction where the
definition declares percent). The fix was structural, not more care:

- **One resolver.** `evidence_context_sync.py` imports the metric-resolution core of
  `wren_context_sync.py` — semantic-model lookups, dimension joins, filter templates,
  the per-type SQL builders. Tiers share the code that decides what a metric means.
- **Generation ownership.** Compiled files carry a generation header; the sync refuses
  to overwrite a file without it and deletes generation-owned orphans. A hand edit in
  generated space is surfaced, never silently kept.
- **Oracles, not snapshots.** The gates compare against hand-written SQL restating each
  definition independently — a compiler bug and its snapshot cannot agree their way
  past the gate.

Full design: `code-skills/docs/EVIDENCE_INTEGRATION.md` (this tier),
`code-skills/docs/SEMANTIC_LAYER_ALIGNMENT.md` (the doctrine, measured).

## Changing a metric

1. Edit `models/semantic/_metrics.yml` (or `_semantic_models.yml`) in the use-case.
2. `./scripts/e2e.sh` — rebuild, recompile, gate, pull, dashboard build.
3. Review the diff: the definition change *and* its compiled consequences across
   `wren/views/`, `evidence/queries/`, and the pulled copies in `evidence-bi/`.
4. Commit in each submodule, then bump both pointers here in one umbrella commit —
   the pinned pair is the tested metric contract.

## Every use-case gets a tier: the evidence-skills pack

`code-skills/skill-packs/evidence-skills/` packages the whole method as agent
skills — activated into `.claude/` beside the dbt/wren/lightdash packs:

- **evidence-tier** (canonical): give any use-case its Evidence tier from its
  own ontology and semantic layer — prerequisites, `evidence.yml` cuts, the
  source adapter, the stage, the gates, the pages.
- **evidence-pages**: page craft (anatomy, forms, validated color system,
  component cookbook, enterprise reports) with the four reference docs.
- `/evidence <slug> [--check|--pages|--serve]` and `evidence-rules.md`.

Both use-cases now carry working tiers. `example-order-revenue-mart` is the
flagship (7 metrics + saved query, oracle-gated). `enhanza-analytics` — the
multi-connector ERP — serves what its ontology's honesty rules admit today:
the conformed-dimension estate and the supplier metric, cut by country and
active state, with a metric dictionary that lists the twenty blocked concepts
*and why* (grain tests, additivity annotations) as the growth path. Its demo
warehouse builds from sample seeds
(`dbt build --target demo` on the tripletex + visma_eaccounting covering set),
and `tests/test_evidence_bundles.py` executes every bundle against its own
warehouse — the fleet gate that keeps "every use-case" true as new ones land.

Serve either one: `DBT_PROJECT_DIR=../code-skills/skill-packs/dbt-skills/use-cases/<slug>/dbt_project ./scripts/sync-dbt.sh`
— the sync pulls the warehouse, the compiled queries, the adapter, *and the
bundle's pages*, so the app is the frame and the use-case brings the content.

## New use-cases

Scaffold in the data platform, declare the Evidence tier, wire the BI project:

```bash
cd code-skills
.venv/bin/python scripts/use_case_sync.py --init <slug>       # ontology + spec skeleton
# ... build the dbt project + semantic models (see the dbt-skill) ...
cp skill-packs/dbt-skills/use-cases/example-order-revenue-mart/evidence.yml \
   skill-packs/dbt-skills/use-cases/<slug>/evidence.yml        # then edit the cuts
# write evidence/sources/<schema>/*.sql — the per-semantic-model extractions
.venv/bin/python scripts/use_case_sync.py --use-case <slug> --stage evidence
```

Point the BI project at it: `DBT_PROJECT_DIR=../code-skills/skill-packs/dbt-skills/use-cases/<slug>/dbt_project ./scripts/sync-dbt.sh`
(or make it the default in `evidence-bi/scripts/sync-dbt.sh` for a single-use-case
deployment), then write pages that filter, aggregate, and render the compiled columns —
never redefine them.

## Submodule hygiene

- `git submodule update --init` after clone; `--remote` only when deliberately moving
  to newer platform commits — then run `./scripts/e2e.sh` before committing the bump.
- Work happens in the submodules on branches, PRs merge there, the umbrella pins the
  merged SHAs. The umbrella never carries platform patches of its own.

# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
CANDID is pre-release, so everything lives under **Unreleased** until the first
tagged version; entries are grouped by theme rather than by date.

## [Unreleased]

### Added

#### Deterministic ranking engine

- Gene-list pipeline: a `candidate_set` input model (multi-source, tagged, UI-agnostic),
  batched MyGene resolution to canonical Ensembl ids, and a weighted-mean **composite**
  ranking over normalized per-signal values with a tunable rubric (`rubric.yml`) and
  live weight sliders that re-rank without re-querying.
- **Dual-mode discovery**: with a disease context, seed a candidate universe from
  Open Targets, PanelApp and DISEASES and rank disease-aware (association, ClinVar and
  co-mention scoped to that disease).
- **Caveats & veto stage** (deterministic anti-familiar-gene-bias): FLAGS-gene veto,
  single-weak-source, common-in-gnomAD (gene-level pLoF frequency), and
  unrelated-tissue caveats — each recording its reason on the candidate.
- Disease-context priors as config (`context/*.yaml`) with an in-app study-context
  selector; NF1 and Lynch syndrome ship as references.

#### Signals & connectors

- Core signals: Open Targets association, Europe PMC mention count, ClinVar,
  gnomAD (LOEUF constraint + opt-in common-variant frequency), Reactome pathway
  membership, STRING within-list connectivity, GTEx tissue expression, PubTator3
  entity-tagged literature, DGIdb, Pharos, and cross-source corroboration.
- A **source catalog** with per-run selection (query-level gating; a deselected
  source is never called) and an in-app Connectors page rendered from that catalog.
- Opt-in connectors: cBioPortal, CIViC, ClinGen, HPO, HPA, Gene Ontology (QuickGO),
  UniProt/Swiss-Prot disease, PDBe, IMPC; plus key-gated catalog stubs.
- Variant-effect clients (Ensembl VEP, gnomAD, ClinVar) and a Europe PMC literature
  client; top article **PMIDs** surfaced as citable literature evidence.

#### Grounding & the AI stages

- **Citation gate**: every evidence row must carry a `source_id` or it is rejected —
  grounding enforced structurally, not by trust.
- Optional interpretive **input agent** (propose → confirm → run; never invents genes).
- Grounded, model-agnostic **AI curator** with a user-set target list size.
- Three parallel **specialist agents** (variant · pathway/disease · literature) with
  orchestrator synthesis into one grounded per-gene verdict + a priority next
  experiment, surfaced in the table, report, and CSV.

#### Interfaces & reporting

- Shiny UI: multi-source tagged input, ranked table with per-gene evidence drill-down,
  "Load NF1 example" button, and the **Connectors**, **AI Agents**, and
  **Reading results** documentation pages.
- R-native auditable HTML + CSV report (webR-safe htmltools).
- UI-agnostic core: a `run_review_request` envelope backing a headless CLI and a
  design-only plumber HTTP service with stdlib-Python / curl client demos.

#### Evaluation & reproducibility

- Eval harness on known NF1 biology (drivers grade High, passenger vetoed last) and a
  **caveats benchmark** quantifying the veto stage's contribution.
- **Identity guard** for the evals: every candidate must resolve to the gene it named
  (round-trip + optional `expect_identity` Ensembl anchors), with an offline test on a
  synthetic mis-resolution so the protection lives in CI; a committed
  `evals/baseline.json` snapshot and an on-demand (`workflow_dispatch`) eval workflow.
- A Lynch-syndrome/MMR eval case alongside NF1.
- Committed `renv.lock` for reproducible builds (Docker uses the same lock); a
  consolidated `docs/methodology.md`.
- Parallel evidence retrieval across a bounded [mirai](https://mirai.r-lib.org/)
  worker pool (serial fallback) for large panels; crash-safe AI stages that run the
  LLM calls in a background process.

### Changed

- Default provider switched to **Google Vertex AI** (Gemini on Vertex); provider and
  model are read from `config.yml`, so switching is a config change, not a code change.
- `run_enrich` consumes a `candidate_set`; the disease seed is modeled as a seeded
  source distinct from the user's real sources.
- HTTP layer hardened: contact-bearing user agent, per-host circuit breaker,
  input-size cap, success-only cache, and preservation of the last-good result on a
  failed re-run.
- Whole-list MyGene resolution collapsed into a single batch request (first-run
  latency).

### Fixed

- **Wrong-gene resolution**: resolve to the exact gene symbol rather than MyGene's
  top-scored fuzzy match (an input of TTN had resolved to TTR).
- Vertex AI authentication: pass project + location to the chat and bundle `gargle`.
- Ground curation citations to each gene's real evidence ids; bound and track
  disease-discovery runs.
- STRING grounding, HGNC reconciliation, and truncation auditing; gnomAD/Pharos
  GraphQL query shapes; selection-gating regressions; surfaced upload errors and
  unresolved-gene feedback.

### Repository hygiene

- prek hooks, CI (format · test · markdown lint), secret scanning, and Conventional
  Commits / protected-`main` conventions.

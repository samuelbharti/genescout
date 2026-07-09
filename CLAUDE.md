# CLAUDE.md

Working context for Claude Code building **CANDID** — an agentic evidence-review
workbench for research genomics. Read this before writing code. The full phased
plan is in `PLAN.md`; this file is the standing project memory and the rules.

## What we are building

CANDID takes a **candidate list** (variants, gene symbols, or perturbation hits)
plus a **biological context** (a disease/config file, e.g. NF1) and produces a
**plausibility-ranked, cited research review** with caveats and suggested next
experiments. It is an R Shiny app with an ellmer-based agent engine: an
orchestrator fans out to parallel specialist agents, a citation gate drops
ungrounded evidence, a caveats stage scores and can veto candidates, and a report
is assembled as an auditable artifact.

## Non-negotiables (do not violate these)

1. **Research use only. Never produce clinical output.** No diagnosis, no treatment
   advice, no ACMG/AMP pathogenicity classification, no "this patient has…". ClinVar
   and gnomAD are used as *research evidence*, not clinical calls. Every report
   carries the research-use-only disclaimer.
2. **No ungrounded claims. Ever.** Every biological assertion in the output must trace
   to a database record or a citation returned by a tool. If a specialist cannot ground
   a statement, it must say "no evidence found," not invent one. Gene names, effect
   sizes, and paper references are never fabricated or recalled from memory — they come
   from tool calls only.
3. **Uncertainty is a feature.** Surface what is weak, conflicting, or missing. Do not
   smooth over gaps to make a candidate look better.
4. **No secrets in the repo.** API keys come from the environment (`ANTHROPIC_API_KEY`,
   etc., via `.Renviron`). Never hardcode keys, never commit `.Renviron`.
5. **Only public/synthetic example data.** Never commit or demo with real patient
   VCFs or any identifiable data. `data/examples/` holds public or synthetic
   candidates only.
6. **Reproducibility is part of correctness.** When you add or change a data source,
   update `docs/data_sources.md` with the source name, endpoint, version/release, and
   access date. Pin dependency versions (`renv.lock`).

## Tech stack

- **Language:** R (≥ 4.3) end to end. One runtime.
- **UI:** Shiny + bslib on the `RShiny_template` scaffold. Page layouts in
  `userInterface/`, reusable module UI/server in `modules/`, utilities and the
  engine in `R/` (auto-sourced by `R/load_components.R`; `R/tools/` is sourced too).
- **Agents:** [ellmer](https://ellmer.tidyverse.org/). Use `chat_anthropic()` (or
  another provider), `chat$register_tool()` for tools, `type_object()` for structured
  extraction, and `parallel_chat_structured()` to fan the specialists out.
- **HTTP:** [httr2](https://httr2.r-lib.org/) for all bio-database clients, through the
  shared wrapper in `R/http.R` (timeout + retry + a small success-only cache).
- **Config:** provider/model roles in `config.yml` (read via `R/config.R`); disease
  context as YAML (`context/*.yaml`).
- **Tests:** `testthat`, offline against recorded fixtures (`httptest2`).

Model defaults live in `config.yml` (roles → provider + model): orchestrator and
caveats on the most capable model; the three retrieval specialists on a faster model
for speed and cost. **Do not hardcode model or provider strings in engine logic —
read them from config.** Switching providers is a config change, not a code change.

## Architecture and where things live

```text
run_review()  (R/orchestrate.R)
  ├─ parses input        → R/parse_input.R (normalized candidate tibble)
  ├─ loads context       → R/context.R (context/<disease>.yaml)
  ├─ builds agents       → R/agents.R (ellmer Chat per role + tool allowlist)
  ├─ spawns specialists (parallel_chat_structured), each isolated:
  │    ├─ variant-effect   → R/tools/variant_effect.R (VEP, gnomAD, ClinVar)
  │    ├─ pathway-disease  → R/tools/pathways.R, R/tools/opentargets.R (+ PAGER)
  │    └─ literature       → R/tools/literature.R (Europe PMC, PubTator)
  ├─ citation gate       → R/citation_gate.R (drop items with no source_id)
  ├─ scoring + caveats   → R/scoring.R (can down-rank / veto)
  └─ report              → R/report.R (auditable HTML/Quarto artifact)
```

- **Specialist agents** are ellmer `Chat` objects. Each gets a tight system prompt
  (`prompts/<role>.md`), a restricted tool allowlist, and its own isolated context.
  A specialist returns only distilled evidence (a `type_object()` schema), never its
  full working context. Every evidence item carries a `source_id`.
- **Tool clients** are thin, individually testable functions in `R/tools/`. One file
  per data source. **No ellmer imports inside tool clients** — they must be callable
  and testable in plain R.
- **The scoring rubric** lives in `prompts/scoring-rubric.md` so ranking logic is
  explicit and reviewable, not buried in a prompt or in code.
- **The disease context** (`context/*.yaml`) carries priors: relevant pathways (e.g.
  RAS/MAPK for NF1), known drivers, tissues of interest, FLAGS genes. Scoring reads
  this so the same engine generalizes across contexts.

## Coding conventions

- Small, pure, testable functions in `R/tools/`. Each client: input → typed list/tibble
  out; raises `candid_http_error` on failure; never returns a half-parsed blob.
- Every tool client goes through the shared `R/http.R` wrapper with timeout, limited
  retry, and a 30-minute success-only cache (never cache failures).
- All external identifiers and versions are logged, not silently assumed.
- Structured returns over free text wherever a downstream stage consumes the output.
- Format with air (`air format .`; config in `air.toml`) - the single R style gate,
  checked in CI. Keep functions small; snake_case (or camelCase) names.
- Write the fixture-backed test alongside each new tool client.

## How to add a new data source (the extension pattern)

1. Add `R/tools/<source>.R` — a pure client through the shared HTTP wrapper.
2. Add an `httptest2` fixture + a parser test in `tests/testthat/`.
3. Expose it to the relevant specialist via that role's allowlist in `R/agents.R`
   (`specialist_tools`) and its prompt in `prompts/`.
4. Record the source in `docs/data_sources.md` (name, endpoint, version, access date).

## The citation gate

`R/citation_gate.R::validate_evidence()` inspects specialist output before it is
accepted: any evidence item lacking a `source_id` (a database accession or a citation
id) is rejected. Because specialists return a `type_object()` schema that requires
`source_id`, grounding is enforced structurally, not by trust. This replaces the Agent
SDK hook from the original design.

## Testing and evals

- Unit/parser tests run offline against fixtures — no live API calls in CI.
- The **eval set** (`evals/test_cases.yaml`) lists known candidates with expected
  relative ranking (e.g. NF1, SUZ12, CDKN2A should rank high in NF1/MPNST context; a
  passenger/housekeeping gene should rank low). `evals/run_evals.R` runs the pipeline
  and checks the ranking holds. Treat a regression here as a real failure — it is the
  spine of the eventual methods paper.

## Working in this repo (workflow)

- **Never commit to `main`** (protected + local `no-commit-to-branch` hook). Branch
  `<type>/<short-desc>`; open a PR. Commit messages and PR titles are **Conventional
  Commits** (`feat:`, `fix:`, `docs:`, `chore:`…). See `CONTRIBUTING.md`.
- Install hooks with prek: `prek install --hook-type pre-commit --hook-type commit-msg`.

## What NOT to do

- Do not add clinical interpretation, diagnosis, or ACMG scoring — even if asked.
- Do not let any agent state a gene/variant/paper fact that did not come from a tool.
- Do not hardcode a provider or model string; read from `config.yml`.
- Do not import ellmer inside `R/tools/` clients — keep them plain, testable R.
- Do not commit keys, `.Renviron`, large data files, or real patient data.
- Do not silently change a data source's version without updating `docs/data_sources.md`.

## Definition of done (per feature)

A feature is done when: it runs on the bundled NF1 example, its output is grounded
(every claim cited), it has a fixture-backed test, and — if it touched a data source —
`docs/data_sources.md` is updated. Start from `PLAN.md`, Phase 0.

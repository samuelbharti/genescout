# CANDID — Build Plan

The plan of record for building CANDID. Read `CLAUDE.md` first for the rules and
architecture. This file sequences the work into phases with explicit acceptance
criteria. **Build the phases in order.** Do not start a phase until the previous
phase's acceptance criteria pass.

## Stack (decided)

R-native, one runtime:

- **UI:** R Shiny + bslib, on the `RShiny_template` scaffold (`global.R` / `ui.R`
  / `server.R`, `modules/`, `userInterface/`, `R/`).
- **Agents:** [ellmer](https://ellmer.tidyverse.org/) — `chat_anthropic()` (or any
  provider), tool calling, `type_object()` structured extraction, and
  `parallel_chat_structured()` for concurrent specialist fan-out.
- **Data:** [httr2](https://httr2.r-lib.org/) clients, one file per source in
  `R/tools/`.
- **Config:** provider/model roles in `config.yml`; disease context in
  `context/*.yaml`. **Deps:** renv (`renv.lock` + `DESCRIPTION`).

## Guiding principles

1. **Thin vertical slice first.** Get one candidate through the entire pipeline —
   input → one data source → grounded summary → rendered report — before adding
   any breadth. A working end-to-end slice beats a half-built six-agent graph.
2. **Grounded or it doesn't ship.** Every claim traces to a tool result. Wire the
   citation gate early so ungrounded output fails loudly from day one.
3. **Evaluate as you go.** The eval set is not a final step; it is how you know a
   change helped. Add cases as capabilities land.
4. **One stack.** R end to end. No second runtime.

---

## Phase 0 — Scaffold and thin slice

**Goal:** the repo installs and one gene flows end to end. *(Scaffold is in place;
the thin slice is the remaining work.)*

Tasks:

- Scaffold on `RShiny_template`; `renv::restore()` works. **(done)**
- Directory skeleton, prompts, `config.yml`, NF1 context, example TSV. **(done)**
- Implement the shared HTTP wrapper (`R/http.R`): timeout, one retry, 30-min
  success-only cache, typed `candid_http_error`.
- Implement **one** tool client end to end: `R/tools/opentargets.R`
  (gene → disease associations) with an `httptest2` fixture + parser test.
- Minimal `run_review()`: read candidates, call the one tool, ask ellmer to
  summarize the returned evidence *with source ids*, render `report.html` via
  `render_report()`.

**Acceptance criteria:**

- `Rscript dev/run_review.R --input data/examples/nf1_candidates.tsv --context nf1
  --out report.html` produces a report where every stated association cites an
  Open Targets record.
- The Open Targets client has a passing offline fixture test
  (`tests/testthat/test-opentargets.R`).

---

## Phase 1 — Parallel specialists + real evidence

**Goal:** three specialist agents run in parallel and return grounded, structured
evidence.

Tasks:

- Flesh out the specialist prompts in `prompts/` and `build_specialist()` in
  `R/agents.R`: tight system prompt, restricted tool allowlist, `type_object()`
  evidence schema (every item has `source_id`).
- Implement remaining tool clients (each with a fixture + test):
  `R/tools/variant_effect.R` (VEP/gnomAD/ClinVar), `R/tools/pathways.R`
  (Reactome/PAGER), `R/tools/literature.R` (Europe PMC/PubTator),
  `R/tools/mygene.R`.
- Fan the three specialists out with `parallel_chat_structured()` in
  `run_review()` and collect distilled evidence per candidate.
- Implement the **citation gate** (`R/citation_gate.R::validate_evidence()`):
  reject any evidence item with no `source_id`.
- Update `docs/data_sources.md` for every new source.

**Acceptance criteria:**

- All three specialists run in parallel on the NF1 example and return structured
  evidence.
- The citation gate rejects a deliberately un-sourced test item.
- Every tool client has a passing offline test.

---

## Phase 2 — Scoring, caveats, and the veto

**Goal:** candidates are ranked by plausibility, and the caveats stage can override.

Tasks:

- Finalize the scoring rubric in `prompts/scoring-rubric.md` (how evidence maps to
  a grade; what a caveat is; what triggers a veto).
- Implement `R/scoring.R::score_candidate()`: combine gated evidence + context
  priors (`context/nf1.yaml`) into a per-candidate score.
- Implement `apply_caveats()`: down-rank or veto when a candidate is common in
  gnomAD, supported only by unrelated-tissue evidence, backed by a single weak
  source, or a known artifact/FLAGS gene. Record *why* on the candidate.

**Acceptance criteria:**

- Report is ranked, and each candidate shows its score, supporting evidence, and
  any caveats.
- A seeded "looks good but is common/weakly supported" candidate is visibly
  down-ranked with a stated reason.

---

## Phase 3 — Report artifact + Shiny UI

**Goal:** a researcher can drive the whole thing from the UI and get an auditable
report.

Tasks:

- Finish `R/report.R`: per-candidate cards (what it is · evidence + citations ·
  caveats · **suggested next experiment/analysis**), a ranked summary table, and
  the research-use-only disclaimer; render `report/template.qmd` to an auditable
  HTML artifact.
- Finish the `modules/` wiring so upload/paste → pick a context → run → view the
  ranked cards → download the report all work.
- Graceful handling of empty input, unknown genes, and API failures.

**Acceptance criteria:**

- End-to-end run through the UI on the NF1 example produces the ranked report with
  citations and next-experiment suggestions.
- Bad input (empty, junk, unknown gene) degrades gracefully, no crash.

---

## Phase 4 — Evals, polish, and submission

**Goal:** demonstrated correctness, a clean demo, and a submitted project.

Tasks:

- Grow `evals/test_cases.yaml` and finish `evals/run_evals.R`; confirm known NF1
  biology ranks as expected.
- Feature-freeze early. Fix only what the demo touches.
- Record a 2–3 minute demo video; finalize `README.md` with a short GIF.
- Verify submission requirements and deadline; submit with buffer.

**Acceptance criteria:**

- `Rscript evals/run_evals.R` passes (known drivers rank high; negatives rank low).
- Fresh clone → `renv::restore()` → example run works from the README alone.
- Demo recorded; project submitted.

---

## Publication-readiness (run in parallel, not last)

- **Provenance:** `docs/data_sources.md` stays accurate — every source, endpoint,
  version/release, access date.
- **Reproducibility:** pinned deps (`renv.lock`); the `Dockerfile` recipe; runnable
  example data.
- **Evaluation:** grow the eval set into a real benchmark — ideally CANDID's ranking
  vs. a naive/no-caveats baseline, showing the caveats stage changes outcomes. That
  contrast is the novelty hook.
- **Attribution:** keep git history clean and authorship explicit; `CITATION.cff` current.
- **Licensing/terms:** MIT on the repo; confirm each API's terms allow programmatic use.
- **Preprint:** once Phases 0–4 are solid, a bioRxiv preprint plants a citable,
  timestamped flag before a methods/evaluation write-up.

## Stretch (only after Phase 4 is green)

- Expose one tool client through an MCP server (ellmer supports MCP via `mcptools`).
- Add perturbation-hit input as a first-class candidate type (beyond variants/genes).
- Add a second disease context to prove generalization.
- Batch mode for large candidate lists (`batch_chat_structured()`) with progress.

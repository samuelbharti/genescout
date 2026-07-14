# Project structure

GeneScout is an R Shiny app (built on a bslib template) with an ellmer-based agent
engine and httr2 bio-database clients. One runtime, one language.

```text
genescout/
├── global.R / ui.R / server.R   App entry: setup, navbar UI, server wiring.
├── _brand.yml                   Colors/fonts/logo (bslib brand).
├── config.yml                   Provider/model per role (read by R/config.R).
├── R/                           Engine + utilities (auto-sourced).
│   ├── load_components.R          Sources R/, R/tools/, modules/, userInterface/.
│   ├── config.R / context.R       Load config.yml and context/*.yaml.
│   ├── parse_input.R              Candidate table/text -> normalized tibble.
│   ├── http.R                    Shared httr2 wrapper (timeout/retry/cache).
│   ├── agents.R                  ellmer Chat builders + evidence schema.
│   ├── orchestrate.R             run_review(): parallel specialist fan-out.
│   ├── citation_gate.R           Reject evidence without a source_id.
│   ├── scoring.R                 Plausibility score + caveats/veto.
│   ├── report.R                  Auditable HTML cards + report.
│   └── tools/                    One bio-DB client per source (no ellmer imports).
├── modules/                     Shiny modules (input, results, report, review).
├── userInterface/               Page layouts (review, about).
├── prompts/                     Agent system prompts + scoring rubric.
├── context/                     Disease-context priors (nf1.yaml).
├── data/examples/               Public/synthetic candidate tables.
├── report/                      Quarto report template.
├── dev/                         Helpers + run_review.R (headless CLI).
├── evals/                       Ranking benchmark (test_cases.yaml + run_evals.R).
├── tests/testthat/              Unit tests (offline).
└── docs/                        data_sources.md, described_plan.md, theming.md.
```

## Where things flow

`parse_input` normalizes candidates -> `orchestrate.run_review` loads the context
and fans out three `agents` specialists in parallel -> `citation_gate` drops
ungrounded evidence -> `scoring` grades and applies caveats/veto -> `report`
renders the auditable artifact (shown in the app or downloaded).

See [`../PLAN.md`](../PLAN.md) for the phased build order and
[`../CLAUDE.md`](../CLAUDE.md) for the standing rules.

# Contributing to CANDID

## Branching & commits

- **Never commit to `main`.** `main` is protected and only changes via pull
  request. A local `no-commit-to-branch` hook blocks direct commits.
- Branch from `main` using `<type>/<short-desc>`, e.g. `feat/open-targets-client`,
  `fix/empty-input`, `docs/data-sources`.
- Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `build`, `ci`,
  `perf`, `style`, `revert`.
- Write **Conventional Commit** messages: `feat: add Open Targets client`. Keep
  commits small and single-concern.
- PR titles must also be Conventional Commits (enforced by the `pr-title`
  workflow). Squash-merge to keep `main` history clean.

## Local setup

1. Restore dependencies: `renv::restore()`.
2. Copy `.Renviron.example` to `.Renviron` and set your provider key
   (e.g. `ANTHROPIC_API_KEY`). `.Renviron` is git-ignored.
3. Install the git hooks with [prek](https://prek.j178.dev):

   ```bash
   prek install --hook-type pre-commit --hook-type commit-msg
   ```

4. Run the app: `shiny::runApp()`. Run the headless pipeline:
   `Rscript dev/run_review.R --input data/examples/nf1_candidates.tsv --context nf1`.

## Project structure

- `R/` - engine + utilities (auto-sourced by `R/load_components.R`).
- `R/tools/` - one thin bio-database client per source (httr2; no ellmer imports).
- `modules/` - reusable Shiny modules; `userInterface/` - page layouts.
- `prompts/` - agent system prompts; `context/` - disease-context priors.
- `config.yml` - provider/model roles. `docs/data_sources.md` - source provenance.

## Ground rules (see `CLAUDE.md`)

- Research use only - no clinical interpretation, diagnosis, or ACMG/AMP calls.
- No ungrounded claims - every biological assertion traces to a tool result.
- No secrets in the repo; only public/synthetic example data.
- When you add/change a data source, update `docs/data_sources.md` and pin versions.

## Style, tests, CI

- Format with [air](https://posit-dev.github.io/air/): `air format .`
- Lint: `lintr::lint_dir(".")` (config in `.lintr`).
- Tests live in `tests/testthat/`. Run: `testthat::test_dir("tests/testthat")`.
- Every push/PR runs `CI` (lint, format, tests, markdown), `Secret scan`
  (gitleaks), and `PR title` (Conventional Commits). Make sure these pass.

# Contributing to GeneScout

Thanks for looking. This is a one-person project, so for anything large please
open an issue first: that way you get an early yes or no instead of sinking time
into work that may not land. Small fixes are welcome as a pull request straight
away.

Please also read the [Code of Conduct](CODE_OF_CONDUCT.md).

## Setup

```r
renv::restore()   # install the pinned dependencies
shiny::runApp()   # run the app
```

The deterministic core needs no key. For the optional AI stages, copy
`.Renviron.example` to `.Renviron` (git-ignored) and set your provider key, for
example `ANTHROPIC_API_KEY`.

To run the pipeline without the app:

```bash
Rscript dev/run_review.R --input data/examples/nf1_candidates.tsv --context nf1
```

Install the git hooks with [prek](https://prek.j178.dev). A local
`no-commit-to-branch` hook keeps you off `main`, which is protected anyway:

```bash
prek install --hook-type pre-commit --hook-type commit-msg
```

## Where code goes

- `R/` for the engine and the utilities. `R/load_components.R` sources them.
- `R/tools/` for the bio-database clients, one thin httr2 client per source,
  with no ellmer imports.
- `modules/` for the Shiny modules, `userInterface/` for the page layouts.
- `prompts/` for the agent prompts, `context/` for the disease-context priors.
- `config.yml` for the provider and model per role.

## Ground rules

The most important ones are below; `CLAUDE.md` covers the rest.

- Research use only. No clinical interpretation, no diagnosis, no ACMG/AMP
  calls.
- No ungrounded claims. Every biological assertion has to trace back to a tool
  result.
- No secrets in the repository, and only public or synthetic example data.
- If you add or change a data source, update `docs/data_sources.md` and pin the
  version.

## Before you open a pull request

Branch from `main` as `<type>/<short-desc>`, for example
`feat/open-targets-client`. Write [Conventional
Commits](https://www.conventionalcommits.org/) messages, and give the pull
request a title in the same form, because a workflow checks it. Merges are squashed.

Then check that all of this passes:

```bash
air format .                              # format, configured in air.toml
```

```r
testthat::test_dir("tests/testthat")      # tests
shiny::runApp()                           # the app still starts
```

On every push and pull request, `CI` runs the format check, the tests, and the
Markdown lint; `Secret scan` runs gitleaks; and `PR title` checks the title.

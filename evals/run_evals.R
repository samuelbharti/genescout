#!/usr/bin/env Rscript
# GeneScout eval harness. Runs the deterministic ranking on known gene lists and
# checks three invariants per case: (1) IDENTITY - every candidate resolves to the
# gene it named (guards the TTN->TTR class of bug); (2) GRADE - the expect_high
# genes grade High; (3) ORDER - the expect_below negative control ranks last. Treat
# a regression here as a real failure - it is the spine of the methods evaluation.
# This harness hits live APIs, so it is run on demand, not in CI.
#
# Run from the repo root:
#   Rscript evals/run_evals.R                  # assert invariants (exit 1 on failure)
#   Rscript evals/run_evals.R --write-baseline # also snapshot outcomes to baseline.json
#
# The baseline (evals/baseline.json) is a committed, reproducible record of what the
# pipeline produced on a given date - each candidate's resolved id, rank, grade, and
# composite. It documents the eval and lets a future run diff for drift; because live
# databases grow, grades/ranks may legitimately move, so the baseline is a snapshot,
# and the pass/fail gate is the invariant assertions above (identity is exact).

source("global.R")

WRITE_BASELINE <- "--write-baseline" %in% commandArgs(trailingOnly = TRUE)
BASELINE_PATH <- "evals/baseline.json"

cases <- yaml::read_yaml("evals/test_cases.yaml")

# Assert every gene in expect_high grades as expect_grade, and (if given) that
# expect_below ranks strictly below all expect_high genes. A `disease` field
# turns on discovery mode (disease-aware signals + PanelApp/DISEASES).
# Returns list(ok = <logical>, record = <baseline record or NULL>). The record is
# the per-case snapshot serialized into baseline.json when --write-baseline is set.
run_case <- function(case) {
  context <- list()
  registry <- genescout_registry
  disease_id <- NULL
  disease_name <- NULL
  if (!is.null(case$disease)) {
    dr <- resolve_disease(case$disease)
    if (!isTRUE(dr$ok) || nrow(dr$matches) == 0) {
      message(sprintf(
        "FAIL (%s): could not resolve disease '%s'",
        case$description,
        case$disease
      ))
      return(list(ok = FALSE, record = NULL))
    }
    disease_id <- dr$matches$id[1]
    disease_name <- dr$matches$name[1]
    context <- list(disease = list(id = disease_id, name = disease_name))
    registry <- genescout_registry_disease
  }
  result <- run_review(
    list(eval = case$candidates),
    case$description %||% "",
    genescout_config,
    registry,
    context = context,
    # Optional per-case source selection (a character vector of connector keys),
    # e.g. an explicit cancer-axis subset. Absent -> the default source set.
    enabled = case$sources
  )
  # Identity first: the resolved gene must BE the gene the candidate named. A
  # ranking eval that only checks grades/order would pass even if an input symbol
  # silently resolved to a different gene (the TTN->TTR regression), so assert
  # identity explicitly - every candidate round-trips to itself, and any named
  # `expect_identity` anchor carries its exact Ensembl id. See R/eval_checks.R.
  id_check <- assert_gene_identity(
    result$genes,
    case$candidates,
    expect_identity = case$expect_identity
  )

  ranks <- stats::setNames(result$genes$rank, toupper(result$genes$symbol))
  grades <- stats::setNames(result$genes$grade, toupper(result$genes$symbol))
  want <- case$expect_grade %||% "High"
  got <- grades[toupper(case$expect_high)]
  ok <- id_check$ok && all(!is.na(got)) && all(got == want)

  # expect_below: the named (negative-control) gene must rank strictly below
  # every OTHER candidate, i.e. last.
  if (!is.null(case$expect_below)) {
    below <- ranks[toupper(case$expect_below)]
    others <- ranks[setdiff(
      toupper(case$candidates),
      toupper(case$expect_below)
    )]
    below_ok <- !is.na(below) &&
      all(!is.na(others)) &&
      below > max(others)
    ok <- ok && below_ok
  }

  if (ok) {
    message(sprintf("PASS (%s)", case$description))
  } else {
    # Lead with the identity failure - a wrong-gene resolution invalidates every
    # downstream grade/rank assertion, so it is the most important thing to see.
    if (!id_check$ok) {
      message(sprintf("  IDENTITY (%s): %s", case$description, id_check$detail))
    }
    detail <- paste(sprintf("%s=%s", case$expect_high, got), collapse = ", ")
    if (!is.null(case$expect_below)) {
      detail <- paste0(
        detail,
        sprintf(
          "; %s rank=%s",
          case$expect_below,
          ranks[toupper(case$expect_below)]
        )
      )
    }
    message(sprintf("FAIL (%s): %s (want %s)", case$description, detail, want))
  }

  # Baseline record: the case's own candidates with their resolved id, rank, grade,
  # and composite - a reproducible snapshot of the outcome (not an assertion).
  g <- result$genes
  cand <- g[toupper(g$symbol) %in% toupper(case$candidates), , drop = FALSE]
  cand <- cand[order(cand$rank), , drop = FALSE]
  record <- list(
    description = case$description %||% "",
    disease = disease_name,
    disease_id = disease_id,
    identity_ok = id_check$ok,
    genes = lapply(seq_len(nrow(cand)), function(i) {
      list(
        symbol = cand$symbol[i],
        gene_id = cand$gene_id[i],
        rank = cand$rank[i],
        grade = cand$grade[i],
        composite = round(cand$composite[i], 4)
      )
    })
  )
  list(ok = ok, record = record)
}

failed <- FALSE
records <- list()
for (case in cases) {
  res <- tryCatch(
    run_case(case),
    error = function(e) {
      message("ERROR (", case$description, "): ", conditionMessage(e))
      list(ok = FALSE, record = NULL)
    }
  )
  if (!isTRUE(res$ok)) {
    failed <- TRUE
  }
  if (!is.null(res$record)) {
    records[[length(records) + 1L]] <- res$record
  }
}

if (WRITE_BASELINE) {
  baseline <- list(
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    note = paste(
      "Reproducible snapshot of the deterministic eval outcomes. Live databases",
      "grow, so grades/ranks may drift; the pass/fail gate is run_evals.R's",
      "invariant assertions (identity exact, drivers High, control last)."
    ),
    cases = records
  )
  jsonlite::write_json(
    baseline,
    BASELINE_PATH,
    pretty = TRUE,
    auto_unbox = TRUE,
    digits = 4,
    # A non-discovery case has no disease; serialize that NULL as JSON null (not {}).
    null = "null"
  )
  message(sprintf("\nWrote %s (%d cases).", BASELINE_PATH, length(records)))
}

if (failed) {
  quit(status = 1L)
}

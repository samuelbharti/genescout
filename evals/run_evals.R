#!/usr/bin/env Rscript
# CANDID eval harness. Runs the deterministic ranking on known gene lists and
# checks that the expected relative ranking holds (known drivers rank above a
# passenger/negative-control gene). Treat a regression here as a real failure -
# it is the spine of the methods evaluation. This harness hits live APIs, so it
# is run on demand, not in CI.
#
# Run from the repo root:  Rscript evals/run_evals.R

source("global.R")

cases <- yaml::read_yaml("evals/test_cases.yaml")

# Assert every gene in expect_high grades as expect_grade, and (if given) that
# expect_below ranks strictly below all expect_high genes. A `disease` field
# turns on discovery mode (disease-aware signals + PanelApp/DISEASES).
run_case <- function(case) {
  context <- list()
  registry <- candid_registry
  if (!is.null(case$disease)) {
    dr <- resolve_disease(case$disease)
    if (!isTRUE(dr$ok) || nrow(dr$matches) == 0) {
      message(sprintf(
        "FAIL (%s): could not resolve disease '%s'",
        case$description,
        case$disease
      ))
      return(FALSE)
    }
    context <- list(
      disease = list(
        id = dr$matches$id[1],
        name = dr$matches$name[1]
      )
    )
    registry <- candid_registry_disease
  }
  result <- run_review(
    list(eval = case$candidates),
    case$description %||% "",
    candid_config,
    registry,
    context = context,
    # Optional per-case source selection (a character vector of connector keys),
    # e.g. an explicit cancer-axis subset. Absent -> the default source set.
    enabled = case$sources
  )
  ranks <- stats::setNames(result$genes$rank, toupper(result$genes$symbol))
  grades <- stats::setNames(result$genes$grade, toupper(result$genes$symbol))
  want <- case$expect_grade %||% "High"
  got <- grades[toupper(case$expect_high)]
  ok <- all(!is.na(got)) && all(got == want)

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
  ok
}

failed <- FALSE
for (case in cases) {
  ok <- tryCatch(
    run_case(case),
    error = function(e) {
      message("ERROR (", case$description, "): ", conditionMessage(e))
      FALSE
    }
  )
  if (!isTRUE(ok)) {
    failed <- TRUE
  }
}

if (failed) {
  quit(status = 1L)
}

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

# Assert every gene in expect_high grades as expect_grade (deterministic support).
run_case <- function(case) {
  result <- run_review(
    list(eval = case$candidates),
    case$description %||% "",
    candid_config,
    candid_registry
  )
  grades <- stats::setNames(result$genes$grade, toupper(result$genes$symbol))
  want <- case$expect_grade %||% "High"
  got <- grades[toupper(case$expect_high)]
  ok <- all(!is.na(got)) && all(got == want)
  if (ok) {
    message(sprintf("PASS (%s)", case$description))
  } else {
    message(sprintf(
      "FAIL (%s): %s (want %s)",
      case$description,
      paste(sprintf("%s=%s", case$expect_high, got), collapse = ", "),
      want
    ))
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

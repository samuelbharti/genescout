#!/usr/bin/env Rscript
# CANDID eval harness. Runs the pipeline on known candidates and checks that the
# expected relative ranking holds (known drivers high, negatives low). Treat a
# regression here as a real failure - it is the spine of the methods evaluation.
#
# Run from the repo root:  Rscript evals/run_evals.R

source("global.R")

cases <- yaml::read_yaml("evals/test_cases.yaml")

run_case <- function(case) {
  candidates <- parse_candidate_lines(paste(case$candidates, collapse = "\n"))
  result <- run_review(candidates, case$context, candid_config)
  # TODO: assert every gene in expect_high ranks above every gene in expect_low
  # within result$ranked, once run_review() is implemented.
  invisible(result)
}

failed <- FALSE
for (case in cases) {
  tryCatch(
    run_case(case),
    candid_not_implemented = function(e) {
      message("PENDING (", case$description, "): ", conditionMessage(e))
    },
    error = function(e) {
      failed <<- TRUE
      message("FAIL (", case$description, "): ", conditionMessage(e))
    }
  )
}

if (failed) {
  quit(status = 1L)
}

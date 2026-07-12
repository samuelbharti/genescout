#!/usr/bin/env Rscript
# LIVE smoke test for parallel enrichment (R/parallel.R). This is NOT a unit test:
# it makes real bio-database calls and spawns mirai worker processes, so it never runs
# in CI. Run it by hand from the app root after touching the enrichment or parallel
# code:
#
#   Rscript dev/smoke_parallel.R
#
# It enriches a real ~15-gene panel twice - once across the mirai worker pool (the
# default) and once forced serial - and checks two things:
#   1. correctness: the two runs agree on which (gene, signal) pairs have evidence, so
#      parallel produces the SAME grounded result as the proven serial path;
#   2. that the parallel path actually engaged (no silent fallback to serial) and is
#      faster on a cold cache.
# A mismatch, a fallback warning, or a parallel run that isn't faster is a failure.

source("global.R") # engine + config from the app root

genes <- c(
  "NF1",
  "TP53",
  "SUZ12",
  "CDKN2A",
  "EGFR",
  "PTEN",
  "RB1",
  "BRAF",
  "KRAS",
  "NRAS",
  "SMARCB1",
  "NF2",
  "TSC1",
  "TSC2",
  "MLH1"
)
cs <- new_candidate_set(list(candid_source(
  genes,
  label = "smoke",
  type = "gene"
)))

# The set of (gene, signal) pairs that came back with evidence - the grounded content
# the two runs must agree on (raw numeric values can wobble between live calls; presence
# is the stable, meaningful invariant).
present_pairs <- function(out) {
  s <- out$signals
  s <- s[s$present, , drop = FALSE] # `present` is always TRUE/FALSE (never NA)
  sort(paste(s$symbol, s$signal_key, sep = "::"))
}

run_timed <- function(label, parallel) {
  message(sprintf("\n=== %s run (candid.parallel = %s) ===", label, parallel))
  warned <- character(0)
  t <- system.time(
    out <- withCallingHandlers(
      withr::with_options(
        list(candid.parallel = parallel),
        run_enrich(cs, "parallel smoke test", candid_config)
      ),
      warning = function(w) {
        warned[[length(warned) + 1L]] <<- conditionMessage(w)
        invokeRestart("muffleWarning")
      }
    )
  )
  message(sprintf("  elapsed: %.1fs", t[["elapsed"]]))
  list(out = out, elapsed = t[["elapsed"]], warnings = warned)
}

# Parallel FIRST so the worker caches are cold; serial SECOND (a different process-local
# cache), so both pay real network latency and the timing comparison is fair.
par <- run_timed("PARALLEL", TRUE)
ser <- run_timed("SERIAL", FALSE)

ok <- TRUE
say <- function(pass, msg) {
  message(sprintf("  [%s] %s", if (pass) "PASS" else "FAIL", msg))
  if (!pass) ok <<- FALSE
}

message("\n=== checks ===")

fell_back <- any(grepl("Parallel enrichment unavailable", par$warnings))
say(!fell_back, "parallel path engaged (no fallback-to-serial warning)")

pp <- present_pairs(par$out)
sp <- present_pairs(ser$out)
say(
  identical(pp, sp),
  sprintf(
    "parallel and serial agree on evidence pairs (parallel %d, serial %d)",
    length(pp),
    length(sp)
  )
)
if (!identical(pp, sp)) {
  message("    only in parallel: ", paste(setdiff(pp, sp), collapse = ", "))
  message("    only in serial:   ", paste(setdiff(sp, pp), collapse = ", "))
}

say(
  par$elapsed < ser$elapsed,
  sprintf(
    "parallel faster than serial (%.1fs vs %.1fs, %.1fx speedup)",
    par$elapsed,
    ser$elapsed,
    ser$elapsed / max(par$elapsed, 0.001)
  )
)

message(sprintf("\n%s", if (ok) "SMOKE TEST PASSED" else "SMOKE TEST FAILED"))
quit(status = if (ok) 0L else 1L)

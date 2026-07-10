#!/usr/bin/env Rscript
# CANDID caveats benchmark - the evaluation's novelty hook.
#
# It quantifies how the deterministic CAVEATS / VETO stage changes the ranking
# versus a no-caveats baseline. Each case is enriched ONCE (the expensive, live-API
# half), then ranked TWICE - with and without the caveats stage - so the only thing
# that differs is the caveats. The demonstrable effect: a prominent passenger /
# sequencing-artifact gene (e.g. TTN) that ranks high on raw multi-source
# prominence in the baseline is demoted to last by the caveats stage. If that stage
# ever stops changing outcomes, this benchmark fails - so it doubles as a
# regression guard on the mechanism that is the paper's contribution.
#
# Hits live APIs; run on demand.  Run from the repo root:
#   Rscript evals/run_benchmark.R

source("global.R")

cases <- yaml::read_yaml("evals/test_cases.yaml")

# Enrich a case once, then rank with and without caveats. Returns a per-gene table
# aligning the two rankings, or NULL if the case's disease could not be resolved.
bench_case <- function(case) {
  context <- list()
  registry <- candid_registry
  if (!is.null(case$disease)) {
    dr <- resolve_disease(case$disease)
    if (!isTRUE(dr$ok) || nrow(dr$matches) == 0) {
      message("SKIP (", case$description, "): disease '", case$disease, "'")
      return(NULL)
    }
    context <- list(
      disease = list(id = dr$matches$id[1], name = dr$matches$name[1])
    )
    registry <- candid_registry_disease
  }
  enriched <- run_enrich(
    list(eval = case$candidates),
    description = case$description %||% "",
    config = candid_config,
    registry = registry,
    context = context,
    enabled = case$sources
  )
  baseline <- rank_result(enriched, caveats = FALSE) # no caveats stage
  candid <- rank_result(enriched, caveats = TRUE) # CANDID (caveats on)

  b <- baseline$genes
  cix <- match(toupper(b$symbol), toupper(candid$genes$symbol))
  tab <- data.frame(
    symbol = b$symbol,
    base_grade = b$grade,
    base_rank = b$rank, # rank within the FULL universe (seeded in discovery)
    cav_grade = candid$genes$grade[cix],
    cav_rank = candid$genes$rank[cix],
    delta_rank = candid$genes$rank[cix] - b$rank, # +ve = demoted by caveats
    stringsAsFactors = FALSE
  )
  # Show only the case's own candidates (in discovery mode the seeder adds ~200
  # genes; the ranks above are still their true position in that full universe).
  tab[toupper(tab$symbol) %in% toupper(case$candidates), , drop = FALSE]
}

fmt_case <- function(case, tab) {
  message("\n== ", case$description, " ==")
  ord <- tab[order(tab$cav_rank), , drop = FALSE]
  message(sprintf(
    "  %-8s %-10s %-9s  ->  %-10s %-9s  %s",
    "gene",
    "base",
    "base#",
    "caveats",
    "cav#",
    "shift"
  ))
  for (i in seq_len(nrow(ord))) {
    r <- ord[i, ]
    shift <- if (r$delta_rank > 0) {
      sprintf("v %d", r$delta_rank)
    } else if (r$delta_rank < 0) {
      sprintf("^ %d", -r$delta_rank)
    } else {
      "-"
    }
    message(sprintf(
      "  %-8s %-10s #%-8d ->  %-10s #%-8d %s",
      r$symbol,
      r$base_grade,
      r$base_rank,
      r$cav_grade,
      r$cav_rank,
      shift
    ))
  }
}

# The headline metric per case: the negative-control gene's demotion by the
# caveats stage (how far it falls, and whether it goes from a top grade to Vetoed).
neg_shift <- function(case, tab) {
  if (is.null(case$expect_below)) {
    return(NULL)
  }
  row <- tab[toupper(tab$symbol) == toupper(case$expect_below), , drop = FALSE]
  if (nrow(row) == 0) {
    return(NULL)
  }
  list(
    gene = row$symbol[1],
    base_grade = row$base_grade[1],
    base_rank = row$base_rank[1],
    cav_grade = row$cav_grade[1],
    cav_rank = row$cav_rank[1],
    demoted = row$cav_rank[1] > row$base_rank[1]
  )
}

failed <- FALSE
shifts <- list()
for (case in cases) {
  tab <- tryCatch(
    bench_case(case),
    error = function(e) {
      message("ERROR (", case$description, "): ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(tab)) {
    next
  }
  fmt_case(case, tab)
  ns <- neg_shift(case, tab)
  if (!is.null(ns)) {
    shifts[[length(shifts) + 1L]] <- ns
    message(sprintf(
      "  -> caveats moved %s from %s #%d to %s #%d",
      ns$gene,
      ns$base_grade,
      ns$base_rank,
      ns$cav_grade,
      ns$cav_rank
    ))
    # The mechanism must MATTER: the negative control must be demoted by caveats.
    if (!isTRUE(ns$demoted)) {
      message("  FAIL: the caveats stage did not demote ", ns$gene)
      failed <- TRUE
    }
  }
}

if (length(shifts) > 0) {
  mean_drop <- mean(vapply(
    shifts,
    function(s) s$cav_rank - s$base_rank,
    numeric(1)
  ))
  vetoed <- sum(vapply(shifts, function(s) s$cav_grade == "Vetoed", logical(1)))
  message("\n== Benchmark summary ==")
  message(sprintf(
    "  Negative controls demoted by the caveats stage: %d/%d (mean +%.1f ranks; %d vetoed)",
    sum(vapply(shifts, function(s) s$demoted, logical(1))),
    length(shifts),
    mean_drop,
    vetoed
  ))
  message(
    "  The caveats stage is what sinks a prominent passenger below the real drivers."
  )
}

if (failed) {
  quit(status = 1L)
}

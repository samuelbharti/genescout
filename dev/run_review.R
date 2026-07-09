#!/usr/bin/env Rscript
# Headless CANDID review. Parses a candidate table, loads a disease context, runs
# the pipeline, and writes an auditable HTML report.
#
# Usage:
#   Rscript dev/run_review.R --input data/examples/nf1_candidates.tsv \
#     --context nf1 --out report.html
#
# Dependency-free arg parsing (matches dev/use_template.R style) so --help works
# without any package installed.

usage <- function() {
  cat(
    "CANDID - headless evidence review\n\n",
    "Usage: Rscript dev/run_review.R --input <table> [options]\n\n",
    "  --input    <path>  candidate table, TSV/CSV        (required)\n",
    "  --context  <id>    disease context id              (default: nf1)\n",
    "  --out      <file>  output HTML report path         (default: report.html)\n",
    "  --help             show this message and exit\n",
    sep = ""
  )
}

parse_flags <- function(args) {
  values <- list()
  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (grepl("^--[^=]+=", arg)) {
      key <- sub("^--([^=]+)=.*$", "\\1", arg)
      values[[key]] <- sub("^--[^=]+=", "", arg)
      i <- i + 1L
    } else if (grepl("^--", arg)) {
      key <- sub("^--", "", arg)
      has_val <- i < length(args) && !grepl("^--", args[[i + 1L]])
      values[[key]] <- if (has_val) args[[i + 1L]] else TRUE
      i <- i + if (has_val) 2L else 1L
    } else {
      i <- i + 1L
    }
  }
  values
}

main <- function() {
  opt <- parse_flags(commandArgs(trailingOnly = TRUE))
  if (isTRUE(opt$help) || is.null(opt$input)) {
    usage()
    quit(status = if (is.null(opt$input) && !isTRUE(opt$help)) 1L else 0L)
  }

  context <- opt$context %||% "nf1"
  out <- opt$out %||% "report.html"

  # Load the engine from the app root; relative source()/config paths resolve there.
  source("global.R")

  candidates <- parse_candidates(list(file = opt$input, text = NULL))
  message(sprintf("Parsed %d candidate(s).", nrow(candidates)))

  result <- tryCatch(
    run_review(candidates, context, candid_config),
    candid_not_implemented = function(e) {
      message("Pipeline stub: ", conditionMessage(e))
      quit(status = 0L)
    }
  )
  render_report(result, out)
  message("Wrote ", out)
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x # nolint: object_name_linter.

if (sys.nframe() == 0L) {
  main()
}

#!/usr/bin/env Rscript
# Headless CANDID gene-list ranking. Reads a gene list, pulls per-source signals,
# ranks by the composite score, and writes an auditable HTML report.
#
# Usage:
#   Rscript dev/run_review.R --input data/examples/nf1_candidates.tsv \
#     --description "NF1-associated MPNST" --out report.html
#
# Dependency-free arg parsing (matches dev/use_template.R style) so --help works
# without any package installed.

usage <- function() {
  cat(
    "CANDID - headless gene-list ranking\n\n",
    "Usage: Rscript dev/run_review.R --input <genes> [options]\n\n",
    "  --input        <path>  gene table (TSV/CSV) or one-per-line   (required)\n",
    "  --description  <text>  free-text study description            (optional)\n",
    "  --out          <file>  output HTML report path   (default: report.html)\n",
    "  --help                 show this message and exit\n",
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

# Read the input as a gene list: a table with a gene column, else plain lines.
read_gene_input <- function(path) {
  tbl <- tryCatch(read_candidate_table(path), error = function(e) NULL)
  if (!is.null(tbl)) {
    return(as.character(tbl$candidate))
  }
  readLines(path, warn = FALSE)
}

main <- function() {
  opt <- parse_flags(commandArgs(trailingOnly = TRUE))
  if (isTRUE(opt$help) || is.null(opt$input)) {
    usage()
    quit(status = if (is.null(opt$input) && !isTRUE(opt$help)) 1L else 0L)
  }

  description <- opt$description %||% ""
  out <- opt$out %||% "report.html"

  # Load the engine from the app root; relative source()/config paths resolve there.
  source("global.R")

  genes <- read_gene_input(opt$input)
  message(sprintf("Read %d gene(s).", length(genes)))

  result <- run_review(
    list(input = genes),
    description,
    candid_config,
    candid_registry
  )
  render_report(result, out)
  message("Wrote ", out)
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x # nolint: object_name_linter.

if (sys.nframe() == 0L) {
  main()
}

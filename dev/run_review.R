#!/usr/bin/env Rscript
# Headless CANDID gene-list ranking. Reads one or more (optionally tagged) gene
# sources, optionally runs the interpretive input agent up front and/or the final
# curator at the end, ranks by the composite score, and writes an auditable HTML
# report. It calls the SAME core functions the Shiny app and the design-only API
# use (curate_input / confirm_input / run_review_request / curate_gene_list), so
# the engine surface is proven UI-agnostic.
#
# Usage:
#   # single source (back-compat)
#   Rscript dev/run_review.R --input data/examples/nf1_candidates.tsv \
#     --description "NF1-associated MPNST" --out report.html
#
#   # multiple tagged sources + agents
#   Rscript dev/run_review.R \
#     --source degs=rnaseq_deg:my_degs.tsv \
#     --source atac=atacseq:my_atac.tsv \
#     --description "NF1-associated MPNST" --agent both --out report.html
#
# Dependency-free arg parsing (matches dev/use_template.R style) so --help works
# without any package installed.

usage <- function() {
  cat(
    "CANDID - headless gene-list ranking\n\n",
    "Usage: Rscript dev/run_review.R (--input <genes> | --source ...) [options]\n\n",
    "  --input        <path>   gene table (TSV/CSV) or one-per-line (one source)\n",
    "  --source  <name[=TYPE]:path>  a tagged source; repeatable for many\n",
    "  --description  <text>   free-text study description             (optional)\n",
    "  --disease      <term>   disease context to seed/score against   (optional)\n",
    "  --tissue  <t1,t2>       tissue(s) of interest for GTEx scoring   (optional)\n",
    "  --agent  <none|input|final|both>  agent involvement   (default: none)\n",
    "  --out          <file>   output HTML report path    (default: report.html)\n",
    "  --help                  show this message and exit\n",
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

# Parse one --source spec: "name=TYPE:path", "name:path", or "path". Returns a
# spec list(name, type, file) that collect_candidate_set() consumes.
parse_source_spec <- function(spec) {
  name <- spec
  type <- "unspecified"
  path <- spec
  if (grepl("=", spec)) {
    name <- sub("=.*$", "", spec)
    rest <- sub("^[^=]*=", "", spec) # TYPE:path
    if (grepl(":", rest)) {
      type <- sub(":.*$", "", rest)
      path <- sub("^[^:]*:", "", rest)
    } else {
      path <- rest
    }
  } else if (grepl(":", spec)) {
    name <- sub(":.*$", "", spec)
    path <- sub("^[^:]*:", "", spec)
  }
  list(name = name, type = type, file = path)
}

# Collect every repeated --source flag into specs (parse_flags keeps only one).
collect_source_specs <- function(args) {
  specs <- list()
  i <- 1L
  while (i <= length(args)) {
    if (args[[i]] == "--source" && i < length(args)) {
      specs[[length(specs) + 1L]] <- parse_source_spec(args[[i + 1L]])
      i <- i + 2L
    } else if (grepl("^--source=", args[[i]])) {
      specs[[length(specs) + 1L]] <- parse_source_spec(
        sub("^--source=", "", args[[i]])
      )
      i <- i + 1L
    } else {
      i <- i + 1L
    }
  }
  specs
}

# Read a single --input as a gene list: a table with a gene column, else lines.
read_gene_input <- function(path) {
  tbl <- tryCatch(read_candidate_table(path), error = function(e) NULL)
  if (!is.null(tbl)) {
    return(as.character(tbl$candidate))
  }
  readLines(path, warn = FALSE)
}

# Print the input agent's proposal as plain text (headless has no editor, so the
# proposal is auto-confirmed; this surfaces what was cleaned/flagged/dropped).
print_proposal <- function(proposal) {
  t <- proposal$tokens
  if (is.null(t) || nrow(t) == 0) {
    return(invisible())
  }
  changed <- t[t$action != "keep", , drop = FALSE]
  message(sprintf(
    "Input agent (%s): %d tokens, %d corrected/flagged/dropped.",
    if (isTRUE(attr(proposal, "ai_used"))) "AI" else "pass-through",
    nrow(t),
    nrow(changed)
  ))
  for (i in seq_len(nrow(changed))) {
    message(sprintf(
      "  %-8s %s -> %s  (%s)",
      changed$action[i],
      changed$original[i],
      changed$symbol[i] %||% "",
      changed$reason[i]
    ))
  }
  st <- proposal$proposed_disease$search_term
  if (!is_blank(st)) {
    message("  proposed disease search term: ", st)
  }
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  opt <- parse_flags(args)
  specs <- collect_source_specs(args)
  if (isTRUE(opt$help) || (is.null(opt$input) && length(specs) == 0)) {
    usage()
    quit(status = if (!isTRUE(opt$help)) 1L else 0L)
  }

  description <- opt$description %||% ""
  out <- opt$out %||% "report.html"
  agent <- tolower(opt$agent %||% "none")

  # Load the engine from the app root; relative source()/config paths resolve there.
  source("global.R")

  cs <- if (length(specs) > 0) {
    collect_candidate_set(specs)
  } else {
    as_candidate_set(list(input = read_gene_input(opt$input)))
  }
  message(sprintf("Read %d source(s).", length(cs)))

  # Input agent (front): propose -> auto-confirm (headless). May propose a disease.
  if (agent %in% c("input", "both")) {
    proposal <- curate_input(cs, description, candid_config)
    print_proposal(proposal)
    cs <- confirm_input(proposal)
    st <- proposal$proposed_disease$search_term
    if (is.null(opt$disease) && !is_blank(st)) {
      opt$disease <- st
    }
  }

  # Disease context: resolve a --disease (or agent-proposed) term to a grounded id.
  disease_ctx <- NULL
  if (!is.null(opt$disease) && !is_blank(opt$disease)) {
    r <- resolve_proposed_disease(opt$disease)
    if (isTRUE(r$ok) && nrow(r$matches) > 0) {
      disease_ctx <- list(id = r$matches$id[1], name = r$matches$name[1])
      message(sprintf(
        "Disease context: %s (%s).",
        disease_ctx$name,
        disease_ctx$id
      ))
    } else {
      message(
        "Could not resolve disease '",
        opt$disease,
        "'; continuing without a disease context."
      )
    }
  }

  registry <- if (!is.null(disease_ctx)) {
    candid_registry_disease
  } else {
    candid_registry
  }
  tissues <- if (!is.null(opt$tissue) && !is_blank(opt$tissue)) {
    trimws(strsplit(opt$tissue, ",")[[1]])
  } else {
    character()
  }
  result <- run_review_request(
    list(
      sources = cs,
      description = description,
      disease = disease_ctx,
      tissues = tissues,
      options = list(caveats = TRUE)
    ),
    config = candid_config,
    registry = registry
  )

  # Final curator (end): grounded AI compaction of the ranked list.
  if (agent %in% c("final", "both")) {
    result$curated <- curate_gene_list(result, candid_config)
  }

  render_report(result, out)
  message("Wrote ", out)
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x # nolint: object_name_linter.

if (sys.nframe() == 0L) {
  main()
}

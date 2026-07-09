# Report rendering. Turns a review result into an auditable artifact: a ranked
# gene x signal table (with a legend explaining the composite), per-gene
# drill-down cards showing the evidence behind each signal, and the
# research-use-only disclaimer.
#
# The same renderers serve the Shiny app (results module) and the downloadable
# standalone HTML. Every signal value and evidence row links to its source.

CANDID_DISCLAIMER <- paste(
  "Research use only. CANDID is a hypothesis-prioritization aid for researchers.",
  "It is not a clinical decision-support tool and does not provide diagnosis,",
  "treatment guidance, or ACMG/AMP variant classification."
)

# Human-readable labels for the evidence domains, in display order.
CANDID_DOMAIN_LABELS <- c(
  `pathway-disease` = "Pathway & disease",
  literature = "Literature",
  `variant-effect` = "Variant / ClinVar",
  constraint = "Constraint (gnomAD)",
  druggability = "Druggability"
)

# --- Ranked gene x signal table ---------------------------------------------

# A display data frame for the ranked matrix: Rank, Gene, one column per signal
# (raw value), Composite, Grade. `registry` is the result$registry summary.
gene_matrix_display <- function(genes, registry) {
  df <- data.frame(
    Rank = genes$rank,
    Gene = genes$symbol,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  for (i in seq_len(nrow(registry))) {
    df[[registry$label[i]]] <- format_signal_value(genes[[registry$key[i]]])
  }
  df[["Composite"]] <- round(genes$composite, 3)
  df[["Grade"]] <- genes$grade
  df[["Caveats"]] <- caveats_count_display(genes)
  df
}

# Per-gene caveat summary for the ranked table: the number of caveats (the reasons
# themselves are in the per-gene drill-down), or an em dash when clean. Defensive:
# a gene matrix built before the caveats stage shows "—" for every row.
caveats_count_display <- function(genes) {
  if (!"caveats" %in% names(genes)) {
    return(rep("—", nrow(genes)))
  }
  vapply(
    seq_len(nrow(genes)),
    function(i) {
      k <- length(genes$caveats[[i]])
      if (k == 0) "—" else as.character(k)
    },
    character(1)
  )
}

# Format a raw signal column for display: integers as counts, fractions to 2 dp,
# missing as an em dash.
format_signal_value <- function(v) {
  ifelse(
    is.na(v),
    "—",
    ifelse(
      v == round(v),
      formatC(v, format = "d", big.mark = ","),
      sprintf("%.2f", v)
    )
  )
}

# The signal legend: what the composite means and each source's role/weight.
registry_legend_html <- function(registry) {
  items <- lapply(seq_len(nrow(registry)), function(i) {
    role <- registry$role[i] %||% "evidence"
    dir_note <- if (identical(registry$direction[i], "lower_better")) {
      " · lower is better"
    } else {
      ""
    }
    htmltools::tags$li(
      htmltools::strong(registry$label[i]),
      sprintf(
        " — %s (%s, weight %.2g%s)",
        registry$source[i],
        role,
        registry$weight[i],
        dir_note
      )
    )
  })
  htmltools::div(
    class = "small text-muted mb-3",
    htmltools::p(
      class = "mb-1",
      paste(
        "Composite = weighted mean of each source's normalized signal.",
        "Evidence sources reward breadth (a missing one counts as 0);",
        "annotation sources (constraint, druggability) only nudge the score up",
        "and never penalize a gene. Rank is by composite (higher first).",
        "The caveats stage then down-weights weak candidates and vetoes",
        "recurrent-artifact (FLAGS) genes to the bottom, with the reason on the",
        "gene."
      )
    ),
    htmltools::tags$ul(class = "mb-0", items)
  )
}

# A flat data frame of the ranked matrix for CSV export: rank, gene, ids, each
# signal's raw + normalized value, coverage, composite, grade, and the input
# list(s) each gene came from.
build_export_csv <- function(result) {
  genes <- result$genes
  reg <- result$registry
  df <- data.frame(
    rank = genes$rank,
    gene = genes$symbol,
    gene_id = genes$gene_id,
    resolved = genes$resolved,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  for (i in seq_len(nrow(reg))) {
    k <- reg$key[i]
    df[[k]] <- genes[[k]]
    df[[paste0(k, "_norm")]] <- round(genes[[paste0(k, "_n")]], 4)
  }
  df$n_sources_present <- genes$n_sources_present
  df$composite <- round(genes$composite, 4)
  df$grade <- genes$grade
  df$vetoed <- if ("vetoed" %in% names(genes)) {
    as.logical(genes$vetoed)
  } else {
    FALSE
  }
  df$caveats <- if ("caveats" %in% names(genes)) {
    vapply(genes$caveats, function(x) paste(x, collapse = " | "), character(1))
  } else {
    ""
  }
  df$input_lists <- vapply(
    genes$input_lists,
    function(x) paste(x, collapse = ";"),
    character(1)
  )
  df
}

# Ranked matrix as a static HTML table (for the download).
ranked_matrix_html <- function(genes, registry) {
  disp <- gene_matrix_display(genes, registry)
  htmltools::tags$table(
    class = "table table-striped",
    htmltools::tags$thead(htmltools::tags$tr(
      lapply(names(disp), htmltools::tags$th)
    )),
    htmltools::tags$tbody(lapply(seq_len(nrow(disp)), function(i) {
      htmltools::tags$tr(lapply(names(disp), function(col) {
        htmltools::tags$td(as.character(disp[i, col]))
      }))
    }))
  )
}

# --- AI curation panel ------------------------------------------------------

# Render a curated selection (from curate_gene_list()) as a card: a banner
# stating whether the AI ran or the deterministic fallback was used, then the
# included genes with confidence + grounded rationale. Pure htmltools (the
# download button is added by the module).
render_curation <- function(curated) {
  ai_used <- isTRUE(attr(curated, "ai_used"))
  note <- attr(curated, "message") %||% attr(curated, "error")
  inc <- curated[which(curated$include), , drop = FALSE]

  banner <- htmltools::div(
    class = paste("alert py-2", if (ai_used) "alert-info" else "alert-warning"),
    htmltools::strong(
      if (ai_used) "AI-curated selection. " else "Composite-rank selection. "
    ),
    if (!is.null(note)) {
      note
    } else if (ai_used) {
      "The model filtered the ranked list to the set below."
    }
  )

  body <- if (nrow(inc) == 0) {
    htmltools::p(class = "text-muted fst-italic", "No genes selected.")
  } else {
    rows <- lapply(seq_len(nrow(inc)), function(i) {
      htmltools::tags$tr(
        htmltools::tags$td(inc$gene_symbol[i]),
        htmltools::tags$td(
          if (is.na(inc$confidence[i])) {
            "—"
          } else {
            sprintf("%.2f", inc$confidence[i])
          }
        ),
        htmltools::tags$td(inc$rationale[i])
      )
    })
    htmltools::tags$table(
      class = "table table-sm",
      htmltools::tags$thead(htmltools::tags$tr(
        htmltools::tags$th("Gene"),
        htmltools::tags$th("Confidence"),
        htmltools::tags$th("Rationale")
      )),
      htmltools::tags$tbody(rows)
    )
  }

  # The gene SELECTION is structurally gated to the ranked candidates, but the
  # free-text rationale is model-written. Say so, so it is never mistaken for an
  # independently citation-gated evidence item (the grounded, source-linked
  # evidence lives in the ranked table + per-gene drill-down).
  caveat <- if (ai_used && nrow(inc) > 0) {
    htmltools::p(
      class = "small text-muted fst-italic mt-1",
      paste(
        "Rationales are the model's summary of the evidence shown for each",
        "gene, not separately citation-gated claims. See the ranked table and",
        "per-gene drill-down for the grounded, source-linked evidence."
      )
    )
  }

  htmltools::tagList(
    htmltools::tags$h4(
      class = "h5",
      sprintf("Curated list (%d genes)", nrow(inc))
    ),
    banner,
    body,
    caveat
  )
}

# A flat data frame of the curated (included) genes for CSV export.
build_curated_csv <- function(curated) {
  inc <- curated[which(curated$include), , drop = FALSE]
  data.frame(
    gene = inc$gene_symbol,
    confidence = round(inc$confidence, 3),
    rationale = inc$rationale,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

# --- Per-gene drill-down ----------------------------------------------------

# One gene's evidence card: header (symbol, grade, composite, source lists) plus
# the grounded evidence grouped by domain. `gene_row` is a 1-row slice of
# result$genes; `evidence` is result$evidence (filtered here by gene_id).
render_gene_evidence <- function(gene_row, evidence) {
  ev <- evidence[evidence$gene_id == gene_row$gene_id, , drop = FALSE]
  lists <- gene_row$input_lists[[1]]
  htmltools::div(
    class = "card mb-3",
    htmltools::div(
      class = "card-body",
      htmltools::tags$h4(
        class = "h5",
        gene_row$symbol,
        htmltools::span(
          class = "badge text-bg-secondary ms-2",
          gene_row$grade
        ),
        htmltools::span(
          class = "text-muted ms-2 small",
          sprintf("composite %.3f", gene_row$composite)
        )
      ),
      if (!isTRUE(gene_row$resolved)) {
        htmltools::div(
          class = "alert alert-warning py-1 px-2",
          if (nrow(ev) > 0) {
            paste(
              "Gene symbol could not be resolved to a canonical id; only",
              "disease-seed (symbol-keyed) signals were gathered."
            )
          } else {
            "Gene symbol could not be resolved; no signals were gathered."
          }
        )
      },
      if (length(lists) > 0) {
        htmltools::p(
          class = "small text-muted",
          paste0("From list(s): ", paste(lists, collapse = ", "))
        )
      },
      caveats_block(gene_row),
      evidence_sections(ev)
    )
  )
}

# The caveats/veto banner for a gene's drill-down: a red alert when vetoed, an
# amber one for down-weighting caveats, listing each recorded reason. NULL when
# the gene is clean or predates the caveats stage.
caveats_block <- function(gene_row) {
  if (!"caveats" %in% names(gene_row)) {
    return(NULL)
  }
  reasons <- gene_row$caveats[[1]]
  if (length(reasons) == 0) {
    return(NULL)
  }
  vetoed <- "vetoed" %in% names(gene_row) && isTRUE(gene_row$vetoed[1])
  htmltools::div(
    class = paste(
      "alert py-2",
      if (vetoed) "alert-danger" else "alert-warning"
    ),
    htmltools::strong(if (vetoed) "Vetoed. " else "Caveats. "),
    htmltools::tags$ul(
      class = "mb-0",
      lapply(reasons, htmltools::tags$li)
    )
  )
}

# Grounded evidence grouped into per-domain sub-tables. Empty -> a muted note.
evidence_sections <- function(evidence) {
  if (is.null(evidence) || nrow(evidence) == 0) {
    return(htmltools::p(
      class = "text-muted fst-italic",
      "No grounded evidence for this gene."
    ))
  }
  domains <- intersect(names(CANDID_DOMAIN_LABELS), unique(evidence$domain))
  htmltools::tagList(lapply(domains, function(d) {
    sub <- evidence[evidence$domain == d, , drop = FALSE]
    htmltools::tagList(
      htmltools::tags$h5(
        class = "h6 text-muted mt-3",
        CANDID_DOMAIN_LABELS[[d]]
      ),
      evidence_domain_table(sub)
    )
  }))
}

# One domain's evidence rows as a table (finding, detail, source link).
evidence_domain_table <- function(sub) {
  rows <- lapply(seq_len(nrow(sub)), function(i) {
    htmltools::tags$tr(
      htmltools::tags$td(sub$title[i]),
      htmltools::tags$td(sub$detail[i]),
      htmltools::tags$td(htmltools::tags$a(
        href = sub$source_url[i],
        target = "_blank",
        sub$source_id[i]
      ))
    )
  })
  htmltools::tags$table(
    class = "table table-sm",
    htmltools::tags$thead(htmltools::tags$tr(
      htmltools::tags$th("Finding"),
      htmltools::tags$th("Detail"),
      htmltools::tags$th("Source")
    )),
    htmltools::tags$tbody(rows)
  )
}

# --- Standalone HTML report -------------------------------------------------

# Write the full standalone HTML report for `result` to `file`.
render_report <- function(result, file) {
  genes <- result$genes
  doc <- htmltools::tags$html(
    htmltools::tags$head(
      htmltools::tags$meta(charset = "utf-8"),
      htmltools::tags$title("CANDID gene-list review"),
      htmltools::tags$style(candid_report_css())
    ),
    htmltools::tags$body(
      htmltools::div(
        class = "container",
        htmltools::tags$h1("CANDID gene-list review"),
        if (!is_blank(result$description)) {
          htmltools::p(htmltools::strong("Studying: "), result$description)
        },
        htmltools::div(class = "disclaimer", CANDID_DISCLAIMER),
        htmltools::tags$h2("Ranked genes"),
        registry_legend_html(result$registry),
        ranked_matrix_html(genes, result$registry),
        htmltools::tags$h2("Evidence by gene"),
        htmltools::tagList(lapply(seq_len(nrow(genes)), function(i) {
          render_gene_evidence(genes[i, , drop = FALSE], result$evidence)
        })),
        report_footer(result)
      )
    )
  )
  htmltools::save_html(doc, file = file)
  invisible(file)
}

report_footer <- function(result) {
  sources <- vapply(result$provenance, function(s) s$source, character(1))
  htmltools::tags$footer(
    class = "text-muted mt-4",
    htmltools::tags$hr(),
    htmltools::p(paste0("Sources: ", paste(sources, collapse = ", "), ".")),
    htmltools::p(paste0(
      "Subjective AI ranking applied: ",
      if (isTRUE(result$generated_with_llm)) "yes" else "no",
      "."
    ))
  )
}

candid_report_css <- function() {
  paste(
    ".container { max-width: 960px; margin: 2rem auto;",
    "  font-family: system-ui, sans-serif; padding: 0 1rem; }",
    ".disclaimer, .alert { background: #fff3cd; border: 1px solid #ffe69c;",
    "  border-radius: .375rem; }",
    ".disclaimer { padding: .75rem 1rem; margin: 1rem 0; }",
    ".alert { padding: .5rem .75rem; margin: .5rem 0; }",
    "table { border-collapse: collapse; width: 100%; margin: .5rem 0 1.5rem; }",
    "th, td { text-align: left; padding: .35rem .5rem;",
    "  border-bottom: 1px solid #dee2e6; font-size: .95rem; }",
    ".badge { background: #5b6770; color: #fff; padding: .15rem .5rem;",
    "  border-radius: .375rem; font-size: .8rem; }",
    "h1 { margin-bottom: .25rem; } h2 { margin-top: 2rem; }",
    ".card { border: 1px solid #dee2e6; border-radius: .5rem; margin: 1rem 0; }",
    ".card-body { padding: 1rem 1.25rem; }",
    ".card h4, .card .h5 { margin-top: 0; } .text-muted { color: #6c757d; }",
    ".small { font-size: .85rem; }",
    sep = "\n"
  )
}

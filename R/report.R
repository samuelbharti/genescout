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
  `variant-effect` = "Variant / ClinVar"
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
  df
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

# The signal legend: what the composite means and each source's weight.
registry_legend_html <- function(registry) {
  items <- lapply(seq_len(nrow(registry)), function(i) {
    htmltools::tags$li(
      htmltools::strong(registry$label[i]),
      sprintf(
        " — %s (weight %.2g)",
        registry$source[i],
        registry$weight[i]
      )
    )
  })
  htmltools::div(
    class = "small text-muted mb-3",
    htmltools::p(
      class = "mb-1",
      paste(
        "Composite score = weighted mean of each source's normalized signal;",
        "a missing signal counts as 0. Rank is by composite (higher first)."
      )
    ),
    htmltools::tags$ul(class = "mb-0", items)
  )
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
          "Gene symbol could not be resolved; no signals were gathered."
        )
      },
      if (length(lists) > 0) {
        htmltools::p(
          class = "small text-muted",
          paste0("From list(s): ", paste(lists, collapse = ", "))
        )
      },
      evidence_sections(ev)
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

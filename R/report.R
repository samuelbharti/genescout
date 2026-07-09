# Report rendering. Turns a review result into an auditable artifact: per-
# candidate cards (what it is - grounded evidence with citations - caveats -
# suggested next step), a ranked summary table, and the research-use-only
# disclaimer.
#
# render_candidate_cards() returns Shiny UI for the app; render_report() writes a
# standalone HTML file (used by the download button and the CLI). Every stated
# association links to its Open Targets record.

CANDID_DISCLAIMER <- paste(
  "Research use only. CANDID is a hypothesis-prioritization aid for researchers.",
  "It is not a clinical decision-support tool and does not provide diagnosis,",
  "treatment guidance, or ACMG/AMP variant classification."
)

# Build the per-candidate evidence cards as a Shiny tagList. Plain divs with
# Bootstrap card classes (the app loads Bootstrap via bs_theme, and the
# standalone report styles .card/.card-body itself), so the same renderer serves
# both the app and the downloadable report - and it avoids bslib::card runtime
# machinery.
render_candidate_cards <- function(candidates) {
  htmltools::tagList(lapply(candidates, candidate_section_html))
}

# Alias kept for the report assembly path.
candidate_sections_html <- render_candidate_cards

candidate_section_html <- function(candidate) {
  header <- htmltools::tags$h3(
    class = "h5",
    candidate$symbol %||% candidate$candidate,
    htmltools::span(
      class = "badge text-bg-secondary ms-2",
      candidate$grade %||% "-"
    )
  )
  body <- if (isTRUE(candidate$ok)) {
    htmltools::tagList(
      header,
      if (!is_blank(candidate$rationale)) htmltools::p(candidate$rationale),
      if (!is_blank(candidate$narrative)) {
        htmltools::p(htmltools::em(candidate$narrative))
      },
      evidence_sections(candidate$evidence),
      caveats_html(candidate$caveats),
      if (!is_blank(candidate$next_step)) {
        htmltools::p(htmltools::strong("Next step: "), candidate$next_step)
      }
    )
  } else {
    htmltools::tagList(
      header,
      htmltools::div(class = "text-muted", candidate$error %||% "No evidence.")
    )
  }
  htmltools::div(class = "card mb-3", htmltools::div(class = "card-body", body))
}

# Human-readable labels for the evidence domains, in display order.
CANDID_DOMAIN_LABELS <- c(
  `pathway-disease` = "Pathway & disease",
  literature = "Literature",
  `variant-effect` = "Variant effect"
)

# Grounded evidence grouped into per-domain sub-tables. Each row links to its
# source record; empty evidence renders a muted note.
evidence_sections <- function(evidence) {
  if (is.null(evidence) || nrow(evidence) == 0) {
    return(htmltools::p(
      class = "text-muted fst-italic",
      "No grounded evidence."
    ))
  }
  domains <- intersect(names(CANDID_DOMAIN_LABELS), unique(evidence$domain))
  htmltools::tagList(lapply(domains, function(d) {
    sub <- evidence[evidence$domain == d, , drop = FALSE]
    htmltools::tagList(
      htmltools::tags$h4(
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

# Caveats as a small list, or nothing when there are none.
caveats_html <- function(caveats) {
  if (length(caveats) == 0) {
    return(NULL)
  }
  htmltools::div(
    class = "alert alert-warning py-2 px-3",
    htmltools::strong("Caveats: "),
    htmltools::tags$ul(lapply(caveats, htmltools::tags$li))
  )
}

# Ranked summary table as HTML.
ranked_table_html <- function(ranked) {
  rows <- lapply(seq_len(nrow(ranked)), function(i) {
    htmltools::tags$tr(
      htmltools::tags$td(ranked$symbol[i]),
      htmltools::tags$td(ranked$grade[i]),
      htmltools::tags$td(formatC(ranked$score[i], format = "f", digits = 3)),
      htmltools::tags$td(ranked$top_disease[i]),
      htmltools::tags$td(ranked$n_evidence[i])
    )
  })
  htmltools::tags$table(
    class = "table table-striped",
    htmltools::tags$thead(htmltools::tags$tr(
      htmltools::tags$th("Gene"),
      htmltools::tags$th("Grade"),
      htmltools::tags$th("Score"),
      htmltools::tags$th("Top disease"),
      htmltools::tags$th("# evidence")
    )),
    htmltools::tags$tbody(rows)
  )
}

# Write the full standalone HTML report for `result` to `file`.
render_report <- function(result, file) {
  ctx <- result$context
  doc <- htmltools::tags$html(
    htmltools::tags$head(
      htmltools::tags$meta(charset = "utf-8"),
      htmltools::tags$title("CANDID evidence review"),
      htmltools::tags$style(candid_report_css())
    ),
    htmltools::tags$body(
      htmltools::div(
        class = "container",
        htmltools::tags$h1("CANDID evidence review"),
        htmltools::p(
          htmltools::strong("Context: "),
          ctx$label %||% ctx$id %||% "unspecified"
        ),
        htmltools::div(class = "disclaimer", CANDID_DISCLAIMER),
        htmltools::tags$h2("Ranked candidates"),
        ranked_table_html(result$ranked),
        htmltools::tags$h2("Evidence"),
        candidate_sections_html(result$candidates),
        report_footer(result)
      )
    )
  )
  htmltools::save_html(doc, file = file)
  invisible(file)
}

report_footer <- function(result) {
  sources <- vapply(
    result$provenance,
    function(s) s$source,
    character(1)
  )
  htmltools::tags$footer(
    class = "text-muted mt-4",
    htmltools::tags$hr(),
    htmltools::p(paste0("Sources: ", paste(sources, collapse = ", "), ".")),
    htmltools::p(paste0(
      "Narrative generated with an LLM: ",
      if (isTRUE(result$generated_with_llm)) "yes" else "no",
      "."
    ))
  )
}

candid_report_css <- function() {
  paste(
    ".container { max-width: 900px; margin: 2rem auto;",
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
    ".card h3, .card .h5 { margin-top: 0; } .text-muted { color: #6c757d; }",
    sep = "\n"
  )
}

# Results module: render the ranked gene x signal table, a legend explaining the
# composite score, an optional AI-curated compact list, and a per-gene drill-down
# (the evidence behind each signal) when a row is selected. Empty state until a
# result is available.

results_ui <- function(id) {
  ns <- NS(id)

  tagList(
    uiOutput(ns("empty_state")),
    uiOutput(ns("legend")),
    DT::DTOutput(ns("ranked_table")),
    uiOutput(ns("curate_control")),
    uiOutput(ns("curation")),
    uiOutput(ns("drilldown"))
  )
}

# `result` is a reactive returning the run_review() output (or NULL). `config` is
# the provider/model config the AI curator uses. `agent_mode` is a reactive of the
# selected agent involvement; the final curator is offered only for final/both.
results_server <- function(
  id,
  result,
  config = candid_config,
  agent_mode = reactive("final")
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    final_curator_on <- reactive(agent_mode() %in% c("final", "both"))

    output$empty_state <- renderUI({
      if (is.null(result())) {
        div(
          class = "text-muted p-4",
          h5("No ranking yet"),
          p("Paste genes (optionally describe your study), then Rank genes.")
        )
      }
    })

    output$legend <- renderUI({
      req(result())
      registry_legend_html(result()$registry)
    })

    ranked_display <- reactive({
      req(result())
      gene_matrix_display(result()$genes, result()$registry)
    })

    output$ranked_table <- DT::renderDT({
      req(ranked_display())
      DT::datatable(
        ranked_display(),
        rownames = FALSE,
        selection = "single",
        options = list(pageLength = 25)
      )
    })

    # --- AI curation (the final compaction step) ------------------------------
    curated <- reactiveVal(NULL)

    # Reset any prior curation when the ranking changes - including when a failed
    # re-run clears it to NULL (ignoreNULL = FALSE), so a stale AI-curated card and
    # its CSV never outlive the ranking they were built from.
    observeEvent(result(), curated(NULL), ignoreNULL = FALSE)

    output$curate_control <- renderUI({
      req(result())
      if (!final_curator_on()) {
        return(NULL)
      }
      div(
        class = "my-3",
        actionButton(
          ns("do_curate"),
          "Curate with AI →",
          class = "btn-primary"
        ),
        span(
          class = "text-muted small ms-2",
          paste(
            "Filter the ranked list to a compact set for your study.",
            "The model picks only from the ranked candidates; its rationales",
            "summarize the evidence shown - the grounded, source-linked evidence",
            "stays in the table and drill-down above."
          )
        )
      )
    })

    observeEvent(input$do_curate, {
      req(result())
      req(final_curator_on())
      cur <- tryCatch(
        withProgress(
          message = "Curating with the configured model...",
          curate_gene_list(result(), config)
        ),
        error = function(e) {
          showNotification(
            paste("Curation failed:", conditionMessage(e)),
            type = "error"
          )
          NULL
        }
      )
      curated(cur)
    })

    output$curation <- renderUI({
      req(result()) # never show a curated card without a current ranking
      cur <- curated()
      if (is.null(cur)) {
        return(NULL)
      }
      div(
        class = "card mb-3",
        div(
          class = "card-body",
          downloadButton(
            ns("curated_download"),
            "Download curated list (CSV)",
            class = "btn-outline-secondary btn-sm mb-2"
          ),
          render_curation(cur)
        )
      )
    })

    output$curated_download <- downloadHandler(
      filename = function() "candid_curated.csv",
      content = function(file) {
        req(result())
        req(curated())
        utils::write.csv(
          build_curated_csv(curated()),
          file,
          row.names = FALSE
        )
      }
    )

    output$drilldown <- renderUI({
      req(result())
      sel <- input$ranked_table_rows_selected
      if (is.null(sel) || length(sel) == 0) {
        return(div(
          class = "text-muted p-2 fst-italic",
          "Select a gene in the table to see the evidence behind its signals."
        ))
      }
      render_gene_evidence(
        result()$genes[sel, , drop = FALSE],
        result()$evidence
      )
    })
  })
}

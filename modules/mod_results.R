# Results module: render the ranked gene x signal table, a legend explaining the
# composite score, and a per-gene drill-down (the evidence behind each signal)
# when a row is selected. Shows an empty state until a result is available.

results_ui <- function(id) {
  ns <- NS(id)

  tagList(
    uiOutput(ns("empty_state")),
    uiOutput(ns("legend")),
    DT::DTOutput(ns("ranked_table")),
    uiOutput(ns("drilldown"))
  )
}

# `result` is a reactive returning the run_review() output (or NULL).
results_server <- function(id, result) {
  moduleServer(id, function(input, output, session) {
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

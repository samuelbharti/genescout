# Results module: render the ranked candidate table and per-candidate evidence
# cards from a review result. Shows an empty state until a result is available.

results_ui <- function(id) {
  ns <- NS(id)

  tagList(
    uiOutput(ns("empty_state")),
    DT::DTOutput(ns("ranked_table")),
    uiOutput(ns("cards"))
  )
}

# `result` is a reactive returning the run_review() output (or NULL).
results_server <- function(id, result) {
  moduleServer(id, function(input, output, session) {
    output$empty_state <- renderUI({
      if (is.null(result())) {
        div(
          class = "text-muted p-4",
          h5("No review yet"),
          p("Provide a candidate list and a context, then run a review.")
        )
      }
    })

    output$ranked_table <- DT::renderDT({
      req(result())
      # Expected: a ranked data frame of candidates with score + caveats.
      DT::datatable(result()$ranked, rownames = FALSE)
    })

    output$cards <- renderUI({
      req(result())
      # Expected: one evidence card per candidate (rendered in report.R).
      render_candidate_cards(result()$candidates)
    })
  })
}

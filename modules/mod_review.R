# Review module: the top-level coordinator for the Review tab. Composes the
# input, results, and report sub-modules. On "Rank genes" it runs the expensive
# enrichment once (run_enrich), then re-ranks reactively (rank_result) whenever a
# weight slider moves - no re-query. Failures surface as notifications.

review_ui <- function(id) {
  ns <- NS(id)

  layout_sidebar(
    sidebar = sidebar(
      title = "Genes & study",
      width = 360,
      input_ui(ns("input")),
      report_ui(ns("report"))
    ),
    results_ui(ns("results"))
  )
}

review_server <- function(
  id,
  config = candid_config,
  registry = candid_registry
) {
  moduleServer(id, function(input, output, session) {
    inputs <- input_server("input", registry)
    # The enriched (unranked) result, recomputed only on a "Rank genes" click.
    enriched <- reactiveVal(NULL)

    observeEvent(inputs$run(), {
      lists <- inputs$gene_lists()
      if (length(lists) == 0) {
        showNotification(
          "Provide at least one gene (paste a list or upload a table).",
          type = "error"
        )
        return()
      }
      out <- tryCatch(
        withProgress(
          message = "Pulling source signals...",
          run_enrich(lists, inputs$description(), config, registry)
        ),
        error = function(e) {
          showNotification(
            paste("Ranking failed:", conditionMessage(e)),
            type = "error"
          )
          NULL
        }
      )
      enriched(out)
    })

    # The ranked result: pure, cheap, and recomputed whenever the enriched data
    # or the weight sliders change. NULL before the first run (empty state).
    result <- reactive({
      e <- enriched()
      if (is.null(e)) {
        return(NULL)
      }
      rank_result(
        e,
        weights = inputs$weights(),
        coverage_bonus = inputs$coverage_bonus()
      )
    })

    results_server("results", result)
    report_server("report", result)
  })
}

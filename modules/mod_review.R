# Review module: the top-level coordinator for the Review tab. Composes the
# input, results, and report sub-modules, runs the deterministic gene-list
# ranking on demand, and surfaces failures as notifications rather than crashes.

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
    inputs <- input_server("input")
    result <- reactiveVal(NULL)

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
          run_review(lists, inputs$description(), config, registry)
        ),
        error = function(e) {
          showNotification(
            paste("Ranking failed:", conditionMessage(e)),
            type = "error"
          )
          NULL
        }
      )
      result(out)
    })

    results_server("results", result)
    report_server("report", result)
  })
}

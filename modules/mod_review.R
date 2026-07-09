# Review module: the top-level coordinator for the Review tab. Composes the
# input, results, and report sub-modules, runs the pipeline on demand, and
# surfaces engine "not implemented yet" signals as friendly notifications rather
# than crashes.

review_ui <- function(id) {
  ns <- NS(id)

  layout_sidebar(
    sidebar = sidebar(
      title = "Candidates & context",
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
  contexts = candid_contexts
) {
  moduleServer(id, function(input, output, session) {
    inputs <- input_server("input", names(contexts))
    result <- reactiveVal(NULL)

    observeEvent(inputs$run(), {
      candidates <- tryCatch(
        parse_candidates(inputs$source()),
        error = function(e) {
          showNotification(
            paste("Input error:", conditionMessage(e)),
            type = "error"
          )
          NULL
        }
      )
      req(candidates)

      out <- tryCatch(
        run_review(candidates, inputs$context(), config),
        candid_not_implemented = function(e) {
          showNotification(conditionMessage(e), type = "warning", duration = 8)
          NULL
        },
        error = function(e) {
          showNotification(
            paste("Review failed:", conditionMessage(e)),
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

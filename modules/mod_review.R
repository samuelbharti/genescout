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
      disease <- inputs$disease()
      if (length(lists) == 0 && is.null(disease)) {
        showNotification(
          paste(
            "Provide a gene list (paste or upload),",
            "or pick a disease context for discovery."
          ),
          type = "error"
        )
        return()
      }
      # Discovery mode when a disease is confirmed: use the disease registry
      # (adds PanelApp + DISEASES) and pass the disease as context.
      active_registry <- if (!is.null(disease)) {
        candid_registry_disease
      } else {
        registry
      }
      context <- if (!is.null(disease)) list(disease = disease) else list()
      message_txt <- if (!is.null(disease)) {
        "Seeding candidate genes + pulling signals..."
      } else {
        "Pulling source signals..."
      }
      out <- tryCatch(
        withProgress(
          message = message_txt,
          run_enrich(
            lists,
            inputs$description(),
            config,
            active_registry,
            context = context
          )
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
        coverage_bonus = inputs$coverage_bonus(),
        caveats = inputs$caveats()
      )
    })

    results_server("results", result, config)
    report_server("report", result)
  })
}

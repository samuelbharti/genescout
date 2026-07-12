# Results module: render the ranked gene x signal table, a legend explaining the
# composite score, an optional AI-curated compact list, and a per-gene drill-down
# (the evidence behind each signal) when a row is selected. Empty state until a
# result is available.

results_ui <- function(id) {
  ns <- NS(id)

  tagList(
    uiOutput(ns("empty_state")),
    # The whole results block appears only once there is a ranking, so the layout
    # stays clean (no empty cards) before the first run.
    conditionalPanel(
      condition = "output.has_result == true",
      ns = ns,
      div(class = "mb-3", uiOutput(ns("results_header"))),
      div(class = "mb-3", uiOutput(ns("legend"))),
      div(class = "mb-3", DT::DTOutput(ns("ranked_table"))),
      uiOutput(ns("curate_control")),
      uiOutput(ns("curation")),
      uiOutput(ns("specialist_control")),
      div(class = "mt-3", uiOutput(ns("drilldown")))
    )
  )
}

# `result` is a reactive returning the run_review() output (or NULL). `config` is
# the provider/model config the AI curator uses. `agent_mode` is a reactive of the
# selected agent involvement; the final curator is offered only for final/both.
results_server <- function(
  id,
  result,
  config = candid_config,
  agent_mode = reactive("final"),
  specialists = reactiveVal(NULL)
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    final_curator_on <- reactive(agent_mode() %in% c("final", "both"))

    output$empty_state <- renderUI({
      if (is.null(result())) {
        div(
          class = "text-muted p-5 text-center",
          h5("No ranking yet"),
          p(
            "Add candidate genes (and, optionally, a study context), then Rank genes."
          )
        )
      }
    })

    # Drives the conditionalPanel that reveals the results block.
    output$has_result <- reactive(!is.null(result()))
    outputOptions(output, "has_result", suspendWhenHidden = FALSE)

    output$results_header <- renderUI({
      req(result())
      n <- nrow(result()$genes)
      div(
        h4("Ranked candidates", class = "mb-1"),
        tags$p(
          class = "text-muted small mb-0",
          sprintf(
            "%d gene%s scored - select a row to see the evidence behind each signal.",
            n,
            if (n == 1) "" else "s"
          )
        )
      )
    })

    # The scoring legend is reference material, so it is tucked into a collapsed
    # accordion rather than pushing the table down the page.
    output$legend <- renderUI({
      req(result())
      bslib::accordion(
        open = FALSE,
        bslib::accordion_panel(
          "How the composite score works",
          registry_legend_html(result()$registry)
        )
      )
    })

    ranked_display <- reactive({
      req(result())
      # Once specialists have run, the ranked table gains a Plausibility column.
      gene_matrix_display(
        result()$genes,
        result()$registry,
        verdicts = specialist_verdicts(specialists() %||% list())
      )
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
      n_ranked <- nrow(result()$genes)
      div(
        class = "my-3",
        div(
          class = "d-flex align-items-end gap-2 flex-wrap",
          div(
            style = "width: 150px;",
            numericInput(
              ns("target_size"),
              "Target list size",
              value = min(CANDID_CURATE_TARGET_DEFAULT, n_ranked),
              min = 1,
              max = n_ranked,
              step = 1
            )
          ),
          actionButton(
            ns("do_curate"),
            "Curate with AI →",
            class = "btn-primary"
          )
        ),
        div(
          class = "text-muted small mt-1",
          paste(
            "The deterministic rank shortlists the top candidates; the model",
            "filters them down to about your target size, choosing only from the",
            "ranked genes and citing the evidence shown. The grounded,",
            "source-linked evidence stays in the table and drill-down above."
          )
        )
      )
    })

    observeEvent(input$do_curate, {
      req(result())
      req(final_curator_on())
      ts <- input$target_size
      if (is.null(ts) || is.na(ts) || ts < 1) {
        ts <- CANDID_CURATE_TARGET_DEFAULT
      }
      cur <- tryCatch(
        withProgress(
          message = "Curating with the configured model...",
          # Run in a background process so Stop/refresh mid-call can't crash the session.
          candid_llm_run(curate_gene_list, result(), config, top_n = ts)
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
          render_curation(cur, result()$genes)
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

    # --- Specialist analysis (optional LLM synthesis over the evidence) --------
    # `specialists` is owned by the review module and shared with the report module
    # (so the download embeds the verdict); this tab triggers and renders it.
    # Clear stale analysis when the ranking changes (ignoreNULL = FALSE so a failed
    # re-run that clears the result also clears the specialist cards).
    observeEvent(result(), specialists(NULL), ignoreNULL = FALSE)

    output$specialist_control <- renderUI({
      req(result())
      if (!final_curator_on()) {
        return(NULL)
      }
      div(
        class = "my-3",
        actionButton(
          ns("do_specialists"),
          "Analyze top candidates with specialists →",
          class = "btn-outline-primary"
        ),
        span(
          class = "text-muted small ms-2",
          paste(
            "Three grounded specialists (variant · pathway/disease · literature)",
            "synthesize each top candidate's own evidence, then an orchestrator",
            "rolls them into one verdict + a priority next experiment. Runs on the",
            "top of your curated list when you have curated, else the top ranked",
            "genes. Select a gene row to read its analysis."
          )
        )
      )
    })

    observeEvent(input$do_specialists, {
      req(result())
      req(final_curator_on())
      # If the user curated first, analyze the top of THAT list; otherwise the top
      # ranked genes. So the flow reads rank -> curate to N -> specialists on the best.
      cur <- curated()
      restrict <- if (!is.null(cur) && "include" %in% names(cur)) {
        inc <- cur$gene_symbol[which(cur$include)]
        if (length(inc) > 0) inc else NULL
      } else {
        NULL
      }
      sp <- tryCatch(
        withProgress(
          message = "Running specialists on the top candidates...",
          # Background process: the specialists' libcurl calls stay out of the session.
          candid_llm_run(
            run_specialists,
            result(),
            config,
            restrict_to = restrict
          )
        ),
        error = function(e) {
          showNotification(
            paste("Specialist analysis failed:", conditionMessage(e)),
            type = "error"
          )
          NULL
        }
      )
      # A graceful "no findings / no credentials" outcome is a notice, not an error.
      if (!is.null(sp) && !isTRUE(sp$ai_used) && !is.null(sp$message)) {
        showNotification(sp$message, type = "message")
      }
      specialists(sp)
    })

    output$drilldown <- renderUI({
      req(result())
      sel <- input$ranked_table_rows_selected
      body <- if (is.null(sel) || length(sel) == 0) {
        div(
          class = "text-muted fst-italic",
          "Select a gene in the table to see the evidence behind its signals."
        )
      } else {
        gene_row <- result()$genes[sel, , drop = FALSE]
        tagList(
          render_specialist_analysis(gene_row, specialists()),
          render_gene_evidence(gene_row, result()$evidence)
        )
      }
      bslib::card(
        bslib::card_header("Evidence"),
        bslib::card_body(body)
      )
    })
  })
}

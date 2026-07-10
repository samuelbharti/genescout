# Review module: the top-level coordinator for the Review tab. Composes the
# input, results, and report sub-modules. On "Rank genes" it runs the expensive
# enrichment once (run_enrich), then re-ranks reactively (rank_result) whenever a
# weight slider moves - no re-query. Failures surface as notifications.

review_ui <- function(id) {
  ns <- NS(id)

  layout_sidebar(
    sidebar = sidebar(
      title = "Set up your review",
      width = 400,
      input_ui(ns("input")),
      bslib::card(
        class = "mb-2",
        bslib::card_header("Export"),
        bslib::card_body(report_ui(ns("report")))
      )
    ),
    div(class = "p-2", results_ui(ns("results")))
  )
}

review_server <- function(
  id,
  config = candid_config,
  registry = candid_registry
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    inputs <- input_server("input", registry)
    # The enriched (unranked) result, recomputed only on a "Rank genes" click.
    enriched <- reactiveVal(NULL)
    # The input agent's proposal awaiting user confirmation (input/both modes).
    pending_proposal <- reactiveVal(NULL)

    # Run the expensive enrichment on a CONFIRMED candidate_set. Shared by the
    # direct path (none/final) and the post-confirm path (input/both).
    enrich_confirmed <- function(cs, disease) {
      active_registry <- if (!is.null(disease)) {
        candid_registry_disease
      } else {
        registry
      }
      context <- if (!is.null(disease)) list(disease = disease) else list()
      # Tissue(s) of interest activate the GTEx expression signal (appended by
      # run_enrich) and its unrelated-tissue caveat.
      tissues <- inputs$tissues()
      if (length(tissues) > 0) {
        context$tissues_of_interest <- tissues
      }
      message_txt <- if (!is.null(disease)) {
        "Seeding candidate genes + pulling signals..."
      } else {
        "Pulling source signals..."
      }
      out <- tryCatch(
        withProgress(
          message = message_txt,
          run_enrich(
            cs,
            inputs$description(),
            config,
            active_registry,
            context = context,
            enabled = inputs$enabled()
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
    }

    observeEvent(inputs$run(), {
      cs <- inputs$candidate_set()
      disease <- inputs$disease()
      if (length(cs) == 0 && is.null(disease)) {
        showNotification(
          paste(
            "Provide a gene list (paste or upload),",
            "or pick a disease context for discovery."
          ),
          type = "error"
        )
        return()
      }
      # Input agent (input/both): propose -> confirm -> run. The two-step path is
      # taken only when the mode asks for it AND an LLM is available; otherwise the
      # one-click path below runs immediately, exactly as before.
      mode <- inputs$agent_mode()
      if (mode %in% c("input", "both") && candid_llm_available(config)) {
        proposal <- tryCatch(
          withProgress(
            message = "Reviewing your input with the agent...",
            curate_input(cs, inputs$description(), config)
          ),
          error = function(e) {
            showNotification(
              paste("Input agent failed:", conditionMessage(e)),
              type = "error"
            )
            NULL
          }
        )
        if (is.null(proposal)) {
          return()
        }
        pending_proposal(proposal)
        show_confirm_modal(ns, proposal)
      } else {
        enrich_confirmed(cs, disease)
      }
    })

    # "Confirm & rank": build the confirmed candidate_set from the (edited) confirm
    # panel and run. User edits are treated as user-provided input.
    observeEvent(input$confirm_run, {
      proposal <- pending_proposal()
      req(proposal)
      removeModal()
      cs <- confirmed_set_from_panel(proposal, input)
      if (length(cs) == 0) {
        showNotification(
          "No genes left after confirmation - nothing to rank.",
          type = "error"
        )
        return()
      }
      enrich_confirmed(cs, inputs$disease())
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

    results_server("results", result, config, agent_mode = inputs$agent_mode)
    report_server("report", result)
  })
}

# Open the confirm panel: the agent's proposal summary + one editable genes box
# per source, pre-filled with the confirmed (kept/corrected) symbols. Editing is
# allowed - a user's own change is treated as user-provided input.
show_confirm_modal <- function(ns, proposal) {
  confirmed <- confirm_input(proposal)
  meta <- proposal$sources
  genes_for <- function(sid) {
    s <- Find(function(x) x$id == sid, confirmed)
    if (is.null(s)) character() else s$genes
  }
  boxes <- lapply(seq_len(nrow(meta)), function(i) {
    sid <- meta$id[i]
    textAreaInput(
      ns(paste0("confirm_", sid)),
      label = sprintf("%s (%s)", meta$label[i], meta$type[i]),
      value = paste(genes_for(sid), collapse = "\n"),
      rows = 4
    )
  })
  showModal(modalDialog(
    title = "Review the agent's proposal",
    render_proposal_summary(proposal),
    tags$hr(),
    tags$p(class = "fw-semibold", "Confirmed genes (edit if needed):"),
    boxes,
    footer = tagList(
      modalButton("Cancel"),
      actionButton(ns("confirm_run"), "Confirm & rank", class = "btn-primary")
    ),
    size = "l",
    easyClose = FALSE
  ))
}

# Build the confirmed candidate_set from the confirm panel's (edited) genes boxes,
# preserving each source's label/type/id from the proposal.
confirmed_set_from_panel <- function(proposal, input) {
  meta <- proposal$sources
  srcs <- list()
  for (i in seq_len(nrow(meta))) {
    txt <- input[[paste0("confirm_", meta$id[i])]]
    genes <- trimws(strsplit(txt %||% "", "\r?\n")[[1]])
    genes <- genes[nzchar(genes)]
    if (length(genes) == 0) {
      next
    }
    srcs[[length(srcs) + 1L]] <- candid_source(
      genes,
      label = meta$label[i],
      type = meta$type[i],
      id = meta$id[i]
    )
  }
  new_candidate_set(srcs)
}

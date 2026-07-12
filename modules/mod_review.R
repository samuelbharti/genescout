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
      # Study-context priors (context/<id>.yaml): FLAGS genes, relevant pathways,
      # tissues, drivers. run_enrich loads them from priors_id and degrades to no
      # priors on a bad id, so a plain run (priors_id = NULL) is unchanged.
      priors_id <- inputs$priors_id()
      if (!is.null(priors_id)) {
        context$priors_id <- priors_id
      }
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
      # Discovery seeds a large gene universe; cap it for interactive runs so a
      # click returns in bounded time (the CLI/eval seeder default stays larger).
      seeder <- function(d) {
        seed_disease_genes(d, max_seed = CANDID_INTERACTIVE_SEED_MAX)
      }
      # A determinate per-gene progress bar so a long disease run visibly advances
      # instead of sitting behind a generic spinner (which read as "stuck").
      on_progress <- function(i, n, sym) {
        setProgress(
          value = i / max(n, 1),
          message = message_txt,
          detail = sprintf("Enriching gene %d of %d (%s)", i, n, sym)
        )
      }
      out <- tryCatch(
        withProgress(
          message = message_txt,
          value = 0,
          run_enrich(
            cs,
            inputs$description(),
            config,
            active_registry,
            context = context,
            enabled = inputs$enabled(),
            seeder = seeder,
            progress = on_progress,
            max_genes = CANDID_INTERACTIVE_INPUT_MAX
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
      # Keep the previous ranking on a failed re-run - the error notification above
      # is enough; wiping a good result on a transient error loses the user's work.
      if (!is.null(out)) {
        enriched(out)
        cap <- pluck_at(out, "context", "input_capped")
        if (!is.null(cap)) {
          showNotification(
            sprintf(
              paste(
                "Your list has %d genes; ranked the first %d to keep the app",
                "responsive. Use the CLI (dev/run_review.R) for the full list."
              ),
              cap$total,
              cap$kept
            ),
            type = "warning",
            duration = 12
          )
        }
        # Flag tokens MyGene could not resolve (typos/aliases), which rank at the
        # bottom with no signals - otherwise a fat-fingered symbol vanishes silently.
        rs <- resolution_summary(out$genes)
        if (rs$unresolved > 0) {
          shown <- paste(head(rs$unresolved_symbols, 8), collapse = ", ")
          more <- if (rs$unresolved > 8) ", ..." else ""
          showNotification(
            sprintf(
              "%d of %d gene%s could not be resolved (ranked at the bottom): %s%s",
              rs$unresolved,
              rs$total,
              if (rs$total == 1) "" else "s",
              shown,
              more
            ),
            type = "warning",
            duration = 12
          )
        }
      }
    }

    observeEvent(inputs$run(), {
      cs <- inputs$candidate_set()
      # Tell the user about an unreadable upload instead of silently dropping it.
      for (er in candidate_parse_errors(cs) %||% list()) {
        showNotification(
          sprintf("Could not read the '%s' source: %s", er$source, er$message),
          type = "error",
          duration = 12
        )
      }
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

    # Specialist synthesis, owned here so both the results tab (which triggers it)
    # and the report module (which embeds the verdict in the download) share it.
    specialists <- reactiveVal(NULL)
    results_server(
      "results",
      result,
      config,
      agent_mode = inputs$agent_mode,
      specialists = specialists
    )
    report_server("report", result, specialists = specialists)
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

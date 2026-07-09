# Input module: collect gene lists (paste + optional upload), a free-text study
# description, and per-source ranking weights. Exposes them as reactives. The
# weight sliders re-rank the cached result live (no re-query, because the
# normalization is absolute); the description is stored for the later AI step.

# `registry` defaults to a freshly built registry (not the `candid_registry`
# global, which global.R defines only after the UI is sourced). Its keys match
# the global, so the slider input ids line up with what input_server() reads.
input_ui <- function(id, registry = candid_signal_registry()) {
  ns <- NS(id)

  tagList(
    textAreaInput(
      ns("paste"),
      "Paste gene symbols (one per line)",
      rows = 6,
      placeholder = "NF1\nSUZ12\nCDKN2A"
    ),
    actionButton(
      ns("load_example"),
      "Load NF1 example genes",
      class = "btn-outline-secondary btn-sm mb-3"
    ),
    fileInput(
      ns("file"),
      "...or upload a gene table (TSV/CSV)",
      accept = c(".tsv", ".csv", ".txt")
    ),
    textAreaInput(
      ns("description"),
      "What are you studying? (optional)",
      rows = 3,
      placeholder = paste(
        "e.g. germline drivers of NF1-associated MPNST",
        "in peripheral nerve"
      )
    ),
    tags$hr(),
    tags$label(
      class = "form-label",
      "Discovery (optional): seed genes from a disease"
    ),
    div(
      class = "input-group input-group-sm mb-2",
      textInput(
        ns("disease"),
        label = NULL,
        placeholder = "e.g. neurofibromatosis type 1"
      ),
      actionButton(
        ns("resolve_disease"),
        "Find",
        class = "btn-outline-secondary"
      )
    ),
    uiOutput(ns("disease_matches")),
    actionButton(ns("run"), "Rank genes", class = "btn-primary w-100"),
    bslib::accordion(
      class = "mt-3",
      open = FALSE,
      bslib::accordion_panel(
        "Ranking weights",
        helpText(
          "Adjust how much each source counts; the table re-ranks instantly",
          "with no re-query."
        ),
        weight_sliders_ui(ns, registry),
        checkboxInput(
          ns("coverage_bonus"),
          "Reward genes supported by many evidence sources",
          value = FALSE
        ),
        checkboxInput(
          ns("caveats"),
          paste(
            "Apply caveats & veto (sink FLAGS sequencing-artifact genes;",
            "down-weight single-weak-source genes)"
          ),
          value = TRUE
        )
      )
    ),
    helpText("Research use only. Not for clinical or diagnostic use.")
  )
}

# One slider per registry signal, initialized from its rubric weight.
weight_sliders_ui <- function(ns, registry) {
  lapply(registry, function(s) {
    sliderInput(
      ns(paste0("w_", s$key)),
      s$label,
      min = 0,
      max = 2,
      value = s$weight,
      step = 0.05
    )
  })
}

input_server <- function(id, registry = candid_registry) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Discovery: resolve a free-text disease/phenotype to ontology candidates the
    # user confirms, then feed the chosen one into the pipeline as context.
    disease_matches <- reactiveVal(NULL)

    observeEvent(input$resolve_disease, {
      term <- input$disease
      if (is_blank(term)) {
        showNotification(
          "Enter a disease or phenotype to search.",
          type = "message"
        )
        return()
      }
      r <- tryCatch(
        resolve_disease(term),
        error = function(e) list(ok = FALSE, error = conditionMessage(e))
      )
      if (!isTRUE(r$ok) || nrow(r$matches) == 0) {
        disease_matches(NULL)
        showNotification(
          paste("No disease match:", r$error %||% "none found"),
          type = "error"
        )
        return()
      }
      disease_matches(r$matches)
    })

    output$disease_matches <- renderUI({
      m <- disease_matches()
      if (is.null(m) || nrow(m) == 0) {
        return(NULL)
      }
      choices <- stats::setNames(m$id, sprintf("%s (%s)", m$name, m$id))
      radioButtons(
        ns("disease_pick"),
        "Pick the disease context:",
        choices = choices,
        selected = m$id[1]
      )
    })

    # Pre-fill the paste box with the bundled NF1 gene list, wrapped so a
    # missing/renamed example surfaces a notice rather than crashing.
    observeEvent(input$load_example, {
      loaded <- tryCatch(
        example_text("nf1_candidates"),
        error = function(e) {
          showNotification(
            paste("Could not load example:", conditionMessage(e)),
            type = "error"
          )
          NULL
        }
      )
      req(loaded)
      updateTextAreaInput(session, "paste", value = loaded)
      showNotification(
        "Loaded the NF1 example gene list. Click Rank genes.",
        type = "message",
        duration = 4
      )
    })

    keys <- vapply(registry, function(s) s$key, character(1))

    list(
      run = reactive(input$run),
      gene_lists = reactive(collect_gene_lists(
        input$paste,
        input$file$datapath
      )),
      description = reactive(input$description),
      # The confirmed disease context (list(id, name)) or NULL. NULL keeps the
      # run in plain enrichment mode.
      disease = reactive({
        m <- disease_matches()
        pick <- input$disease_pick
        if (is.null(m) || is.null(pick) || is_blank(pick)) {
          return(NULL)
        }
        row <- m[m$id == pick, , drop = FALSE]
        if (nrow(row) == 0) {
          return(NULL)
        }
        list(id = row$id[1], name = row$name[1])
      }),
      # Named key -> weight vector from the sliders; falls back to the registry
      # default before the sliders have rendered.
      weights = reactive({
        w <- vapply(
          registry,
          function(s) {
            val <- input[[paste0("w_", s$key)]]
            if (is.null(val)) s$weight else as.numeric(val)
          },
          numeric(1)
        )
        stats::setNames(w, keys)
      }),
      coverage_bonus = reactive(isTRUE(input$coverage_bonus)),
      # Caveats/veto on by default; NULL (pre-render) counts as on.
      caveats = reactive(isTRUE(input$caveats %||% TRUE))
    )
  })
}

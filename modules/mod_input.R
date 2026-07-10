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
    # 1 - Candidate genes ----------------------------------------------------
    bslib::card(
      class = "mb-3",
      bslib::card_header("Candidate genes"),
      bslib::card_body(
        textAreaInput(
          ns("paste"),
          NULL,
          rows = 6,
          placeholder = "Paste gene symbols, one per line\nNF1\nSUZ12\nCDKN2A"
        ),
        div(
          class = "d-flex gap-2 align-items-center mb-2",
          actionButton(
            ns("load_example"),
            "Load NF1 example",
            class = "btn-outline-secondary btn-sm"
          ),
          tags$span(class = "text-muted small", "or upload a table below")
        ),
        fileInput(
          ns("file"),
          NULL,
          accept = c(".tsv", ".csv", ".txt"),
          placeholder = "gene table (TSV/CSV)"
        ),
        # Progressive disclosure: the paste box above is the default single source;
        # "add a source" reveals named/typed rows for genes from a different
        # analysis (WES calls, DEGs, ATAC-seq hits, ...). A gene found in more of
        # your sources ranks higher (cross-source corroboration, automatic).
        actionLink(
          ns("add_source"),
          "+ add another source (tag by assay)",
          class = "small d-block"
        ),
        tags$div(id = ns("sources_anchor"), class = "mt-2")
      )
    ),
    # 2 - Study context ------------------------------------------------------
    bslib::card(
      class = "mb-3",
      bslib::card_header("Study context"),
      bslib::card_body(
        textAreaInput(
          ns("description"),
          "What are you studying? (optional)",
          rows = 3,
          placeholder = paste(
            "e.g. germline drivers of NF1-associated MPNST",
            "in peripheral nerve"
          )
        ),
        tags$label(
          class = "form-label small text-muted mb-1",
          "Discovery (optional): seed genes from a disease"
        ),
        div(
          class = "input-group input-group-sm",
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
        textInput(
          ns("tissues"),
          "Tissue(s) of interest (optional)",
          placeholder = "e.g. peripheral nerve, Schwann cell"
        ),
        helpText(
          class = "small",
          "Comma-separated. Genes expressed there (GTEx) score higher; genes",
          "expressed only elsewhere are flagged."
        )
      )
    ),
    # 3 - Run ----------------------------------------------------------------
    bslib::card(
      class = "mb-3",
      bslib::card_header("Run"),
      bslib::card_body(
        agent_mode_ui(ns),
        actionButton(ns("run"), "Rank genes", class = "btn-primary w-100 mt-2")
      )
    ),
    # Advanced (collapsed) ---------------------------------------------------
    bslib::accordion(
      class = "mb-3",
      open = FALSE,
      bslib::accordion_panel(
        "Data sources",
        helpText(
          "Choose which sources to query for per-gene evidence. An unchecked",
          "source is not fetched (saving its network cost); the default set is a",
          "lean, fast core. In a disease-context review the disease still seeds",
          "the candidate list."
        ),
        source_picker_ui(ns)
      ),
      bslib::accordion_panel(
        "Advanced - weights & caveats",
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
    helpText(
      class = "small",
      "Research use only. Not for clinical or diagnostic use."
    )
  )
}

# A checkbox picker of the selectable (per-gene) source connectors, pre-checked to
# the default_on + available subset. Key-gated sources with no key are shown but
# labeled "needs API key" (and left unchecked). The input/network auto-signals
# (cross-source, STRING) are not shown - they append from the run data, not a
# checkbox. Built from candid_source_catalog(), so new connectors appear here for free.
source_picker_ui <- function(ns) {
  catalog <- tryCatch(candid_source_catalog(), error = function(e) list())
  # Only runnable, per-gene connectors are selectable. Stubs (key-gated sources
  # with no live client yet) are catalog/introspection-only - offering one as a
  # checkbox would be a silent no-op, so they are listed separately as "planned".
  sel_cat <- Filter(
    function(s) identical(s$needs %||% "gene", "gene") && !isTRUE(s$stub),
    catalog
  )
  if (length(sel_cat) == 0) {
    return(NULL)
  }
  keys <- vapply(sel_cat, function(s) s$key, character(1))
  labels <- vapply(
    sel_cat,
    function(s) {
      lab <- paste0(s$label, " · ", s$source)
      if (!signal_available(s)) paste0(lab, " (needs API key)") else lab
    },
    character(1)
  )
  selected <- keys[vapply(
    sel_cat,
    function(s) isTRUE(s$default_on %||% TRUE) && signal_available(s),
    logical(1)
  )]
  picker <- checkboxGroupInput(
    ns("sources"),
    NULL,
    choices = stats::setNames(keys, labels),
    selected = selected
  )
  # Key-gated sources CANDID knows about but cannot query yet (no client). Shown as
  # an informational note, never a checkbox, so the picker offers only working ones.
  stub_cat <- Filter(function(s) isTRUE(s$stub), catalog)
  if (length(stub_cat) == 0) {
    return(picker)
  }
  stub_names <- paste(
    vapply(stub_cat, function(s) s$source, character(1)),
    collapse = ", "
  )
  tagList(
    picker,
    helpText(
      class = "fst-italic",
      paste0("Planned (needs an API key): ", stub_names, ".")
    )
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

# One removable extra-source row: a name, an assay type, and a genes box.
extra_source_row <- function(ns, rid) {
  tags$div(
    class = "border rounded p-2 mb-2",
    id = ns(paste0("src_row_", rid)),
    div(
      class = "d-flex gap-2 mb-1",
      textInput(
        ns(paste0("src_name_", rid)),
        label = NULL,
        placeholder = "source name (e.g. my DEGs)"
      ),
      selectInput(
        ns(paste0("src_type_", rid)),
        label = NULL,
        choices = candid_source_types(),
        selected = "unspecified"
      )
    ),
    textAreaInput(
      ns(paste0("src_genes_", rid)),
      label = NULL,
      rows = 3,
      placeholder = "genes for this source, one per line"
    ),
    actionLink(
      ns(paste0("src_rm_", rid)),
      "remove this source",
      class = "small text-danger"
    )
  )
}

# The "Agent involvement" selector. The input/both modes are offered only when an
# LLM key is set; the default "final" preserves today's behavior (final curator
# only). Cross-source corroboration needs no toggle - it applies automatically
# when the run has two or more sources.
agent_mode_ui <- function(ns) {
  llm_ok <- tryCatch(candid_llm_available(), error = function(e) FALSE)
  choices <- if (llm_ok) {
    c(
      "None - deterministic only" = "none",
      "Curate my input up front" = "input",
      "Curate the final list (default)" = "final",
      "Both (input + final)" = "both"
    )
  } else {
    c(
      "None - deterministic only" = "none",
      "Curate the final list (default)" = "final"
    )
  }
  tagList(
    radioButtons(
      ns("agent_mode"),
      "Agent involvement",
      choices = choices,
      selected = "final"
    ),
    if (!llm_ok) {
      helpText(
        class = "small",
        "Set an API key (.Renviron) to enable the input-curation agent."
      )
    }
  )
}

input_server <- function(id, registry = candid_registry) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # The picker's selectable (runnable, per-gene) source keys - used only to tell a
    # genuine deselect-all (character(0) -> query nothing) from a picker that never
    # rendered (NULL -> fall back to defaults). Stubs are excluded (see the picker).
    selectable_source_keys <- tryCatch(
      vapply(
        Filter(
          function(s) identical(s$needs %||% "gene", "gene") && !isTRUE(s$stub),
          candid_source_catalog()
        ),
        function(s) s$key,
        character(1)
      ),
      error = function(e) character(0)
    )

    # Discovery: resolve a free-text disease/phenotype to ontology candidates the
    # user confirms, then feed the chosen one into the pipeline as context.
    disease_matches <- reactiveVal(NULL)

    # Extra tagged sources (beyond the paste box). Rows are added/removed with
    # insertUI/removeUI so typed values survive; `extra_sources` tracks live ids.
    extra_sources <- reactiveVal(character(0))
    row_seq <- reactiveVal(0L)

    observeEvent(input$add_source, {
      n <- row_seq() + 1L
      row_seq(n)
      rid <- as.character(n)
      extra_sources(c(extra_sources(), rid))
      insertUI(
        selector = paste0("#", session$ns("sources_anchor")),
        where = "beforeEnd",
        ui = extra_source_row(ns, rid)
      )
      observeEvent(
        input[[paste0("src_rm_", rid)]],
        {
          removeUI(
            selector = paste0("#", session$ns(paste0("src_row_", rid)))
          )
          extra_sources(setdiff(extra_sources(), rid))
        },
        ignoreInit = TRUE,
        once = TRUE
      )
    })

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

    # The canonical input: a candidate_set built from the paste box (source
    # "pasted"), an optional upload ("uploaded"), and any extra tagged sources.
    # Empty sources are dropped by collect_candidate_set().
    candidate_set_r <- reactive({
      specs <- list()
      if (!is.null(input$paste) && nzchar(trimws(input$paste %||% ""))) {
        specs[[length(specs) + 1L]] <- list(
          name = "pasted",
          type = "unspecified",
          text = input$paste
        )
      }
      fp <- input$file$datapath
      if (!is.null(fp) && nzchar(fp)) {
        specs[[length(specs) + 1L]] <- list(
          name = "uploaded",
          type = "unspecified",
          file = fp
        )
      }
      for (rid in extra_sources()) {
        gv <- input[[paste0("src_genes_", rid)]]
        if (!is.null(gv) && nzchar(trimws(gv %||% ""))) {
          nm <- input[[paste0("src_name_", rid)]]
          specs[[length(specs) + 1L]] <- list(
            name = if (is_blank(nm)) paste0("source ", rid) else nm,
            type = input[[paste0("src_type_", rid)]] %||% "unspecified",
            text = gv
          )
        }
      }
      collect_candidate_set(specs)
    })

    list(
      run = reactive(input$run),
      # The rich candidate_set (canonical) plus the old named-list view for any
      # back-compat caller. run_enrich() accepts either.
      candidate_set = candidate_set_r,
      gene_lists = reactive(candidate_set_to_named_lists(candidate_set_r())),
      agent_mode = reactive(input$agent_mode %||% "final"),
      # The study's tissue(s) of interest (comma-separated), for the GTEx signal.
      tissues = reactive({
        x <- trimws(strsplit(input$tissues %||% "", ",")[[1]])
        x[nzchar(x)]
      }),
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
      caveats = reactive(isTRUE(input$caveats %||% TRUE)),
      # The selected source-connector keys (the Data sources picker). The picker is
      # statically rendered, so by the time "Rank genes" is clicked input$sources is
      # the checked set, or NULL when every box was unchecked - which we map to
      # character(0) so a deselect-all queries nothing (run_enrich errors) instead
      # of silently falling back to the full default set. When the picker never
      # rendered (no selectable sources), NULL correctly means "use defaults".
      enabled = reactive({
        if (length(selectable_source_keys) == 0) {
          return(NULL)
        }
        input$sources %||% character(0)
      })
    )
  })
}

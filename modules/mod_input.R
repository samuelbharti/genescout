# Input module: collect a candidate list (file upload or pasted text) plus the
# disease context, and expose them as reactives. Parsing/validation happens
# downstream in parse_candidates(); this module only gathers raw inputs.

input_ui <- function(id) {
  ns <- NS(id)

  tagList(
    fileInput(
      ns("file"),
      "Upload a candidate table (TSV/CSV)",
      accept = c(".tsv", ".csv", ".txt")
    ),
    textAreaInput(
      ns("paste"),
      "...or paste gene symbols / variants (one per line)",
      rows = 5,
      placeholder = "NF1\nSUZ12\nCDKN2A"
    ),
    actionButton(
      ns("load_example"),
      "Load NF1 example genes",
      class = "btn-outline-secondary btn-sm mb-3"
    ),
    selectInput(ns("context"), "Disease context", choices = NULL),
    actionButton(ns("run"), "Run review", class = "btn-primary w-100"),
    helpText("Research use only. Not for clinical or diagnostic use.")
  )
}

# `contexts` is a named character vector of context ids for the picker.
input_server <- function(id, contexts) {
  moduleServer(id, function(input, output, session) {
    observe({
      updateSelectInput(session, "context", choices = contexts)
    })

    # Pre-fill the paste box with the bundled NF1 gene list and select its
    # context, so a first-time user can run a review with one click. Loading is
    # wrapped so a missing/renamed example file surfaces a notice, not a crash.
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
      if ("nf1" %in% contexts) {
        updateSelectInput(session, "context", selected = "nf1")
      }
      showNotification(
        "Loaded the NF1 example gene list. Click Run review.",
        type = "message",
        duration = 4
      )
    })

    list(
      run = reactive(input$run),
      source = reactive(list(
        file = input$file$datapath,
        text = input$paste
      )),
      context = reactive(input$context)
    )
  })
}

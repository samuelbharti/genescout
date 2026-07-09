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

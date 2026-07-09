# Input module: collect gene lists (paste + optional upload) plus a free-text
# study description, and expose them as reactives. The description is stored for
# the later AI ranking step; the deterministic pipeline uses the genes only.

input_ui <- function(id) {
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
    actionButton(ns("run"), "Rank genes", class = "btn-primary w-100"),
    helpText("Research use only. Not for clinical or diagnostic use.")
  )
}

input_server <- function(id) {
  moduleServer(id, function(input, output, session) {
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

    list(
      run = reactive(input$run),
      gene_lists = reactive(collect_gene_lists(
        input$paste,
        input$file$datapath
      )),
      description = reactive(input$description)
    )
  })
}

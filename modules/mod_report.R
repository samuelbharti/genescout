# Report module: download the auditable HTML report for the current review.
# Disabled until a review result exists.

report_ui <- function(id) {
  ns <- NS(id)

  downloadButton(
    ns("download"),
    "Download report (HTML)",
    class = "btn-outline-secondary"
  )
}

# `result` is a reactive returning the run_review() output (or NULL).
report_server <- function(id, result) {
  moduleServer(id, function(input, output, session) {
    output$download <- downloadHandler(
      filename = function() "candid_report.html",
      content = function(file) {
        req(result())
        render_report(result(), file)
      }
    )
  })
}

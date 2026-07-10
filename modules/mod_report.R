# Report module: download the current review as an auditable HTML report or a
# flat CSV of the ranked table. Both are disabled until a review result exists.

report_ui <- function(id) {
  ns <- NS(id)

  tagList(
    downloadButton(
      ns("download"),
      "Download report (HTML)",
      class = "btn-outline-secondary"
    ),
    downloadButton(
      ns("download_csv"),
      "Download table (CSV)",
      class = "btn-outline-secondary mt-2"
    )
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
    output$download_csv <- downloadHandler(
      filename = function() "candid_ranking.csv",
      content = function(file) {
        req(result())
        utils::write.csv(build_export_csv(result()), file, row.names = FALSE)
      }
    )
  })
}

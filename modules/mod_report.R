# Report module: download the current review as an auditable HTML report or a
# flat CSV of the ranked table. Both are disabled until a review result exists.

report_ui <- function(id) {
  ns <- NS(id)

  div(
    class = "d-flex gap-2 flex-wrap",
    downloadButton(
      ns("download"),
      "Download report (HTML)",
      class = "btn-outline-secondary"
    ),
    downloadButton(
      ns("download_csv"),
      "Download table (CSV)",
      class = "btn-outline-secondary"
    )
  )
}

# `result` is a reactive returning the run_review() output (or NULL). `specialists`
# is the shared run_specialists() reactiveVal (or NULL): when present, the download
# and CSV carry the synthesized verdict/plausibility, not just the drill-down.
report_server <- function(id, result, specialists = reactive(NULL)) {
  moduleServer(id, function(input, output, session) {
    output$download <- downloadHandler(
      filename = function() "genescout_report.html",
      content = function(file) {
        req(result())
        render_report(result(), file, specialists = specialists())
      }
    )
    output$download_csv <- downloadHandler(
      filename = function() "genescout_ranking.csv",
      content = function(file) {
        req(result())
        utils::write.csv(
          build_export_csv(
            result(),
            verdicts = specialist_verdicts(specialists() %||% list())
          ),
          file,
          row.names = FALSE
        )
      }
    )
  })
}

# Report rendering. Turns a review result into an auditable artifact: per-
# candidate cards (what it is - evidence + citations - caveats - suggested next
# experiment), a ranked summary table, and the research-use-only disclaimer.
#
# Two entry points: render_candidate_cards() returns Shiny UI for the app;
# render_report() writes a standalone HTML file (used by the download button and
# the CLI). A Quarto template scaffold lives at report/template.qmd.

# Build the per-candidate evidence cards as a Shiny tagList.
render_candidate_cards <- function(candidates) {
  not_implemented("render_candidate_cards")
}

# Write the full standalone HTML report for `result` to `file`.
render_report <- function(result, file) {
  not_implemented("render_report (auditable HTML artifact)")
}

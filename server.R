# CANDID Shiny server. The Review tab owns the whole pipeline; wire additional
# tabs here as they are added.
function(input, output, session) {
  review_server("review")
}

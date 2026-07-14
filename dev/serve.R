# Run the GeneScout engine as an HTTP service - the UI-agnostic core behind a plain
# JSON API (api/plumber.R). This is how a non-R front end (React / Python / CLI)
# drives the exact same core functions the Shiny app and the CLI use.
#
# Requires plumber (a dev-only dependency, declared in DESCRIPTION Suggests):
#   install.packages("plumber")
# Then, from the app root:
#   Rscript dev/serve.R [port]      # default port 8000
#
# Endpoints (see api/plumber.R): GET /catalog, POST /propose, POST /confirm,
# POST /resolve-disease, POST /review. A worked client demo is in
# dev/engine_client_demo.sh.

library(plumber)

args <- commandArgs(trailingOnly = TRUE)
port <- if (length(args) >= 1 && nzchar(args[1])) {
  as.integer(args[1])
} else {
  8000L
}
if (is.na(port)) {
  port <- 8000L
}

message("Starting GeneScout engine API on http://127.0.0.1:", port)
pr("api/plumber.R") |> pr_run(host = "127.0.0.1", port = port)

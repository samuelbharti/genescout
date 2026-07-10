# Load the app's helper code (utilities, modules, page UI) so that unit and
# server tests can reference it directly. `chdir = TRUE` runs global.R from the
# app root so its relative source() paths resolve.
source(test_path("..", "..", "global.R"), chdir = TRUE)

# Read a recorded API response fixture as parsed JSON (nested lists, matching the
# HTTP layer's simplifyVector = FALSE). Parser tests run fully offline.
read_fixture <- function(name) {
  jsonlite::fromJSON(test_path("fixtures", name), simplifyVector = FALSE)
}

# Read a recorded fixture as raw text (for CSV/TSV bulk-file clients, e.g. ClinGen),
# matching what http_get_text() returns in `text`.
read_fixture_text <- function(name) {
  paste(readLines(test_path("fixtures", name), warn = FALSE), collapse = "\n")
}

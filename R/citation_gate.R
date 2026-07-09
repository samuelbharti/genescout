# Citation gate. Enforces "no ungrounded claims" mechanically: every evidence
# item must carry a non-empty `source_id` (a database accession or citation id).
# Items without one are rejected before they are accepted into a review.
#
# This replaces the Claude Agent SDK hook from the original design; here it is a
# plain validation pass over the specialists' structured output.

# Split evidence into (kept, rejected). `evidence` is a data frame/tibble with at
# least a `source_id` column.
validate_evidence <- function(evidence) {
  not_implemented("validate_evidence (citation gate)")
}

# TRUE if a single evidence item is grounded (has a usable source_id).
is_grounded <- function(item) {
  !is.null(item$source_id) && nzchar(trimws(item$source_id %||% ""))
}

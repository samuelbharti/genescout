# gnomAD gene-constraint client - LOEUF (loss-of-function observed/expected upper
# bound). Endpoint: https://gnomad.broadinstitute.org/api (see docs/data_sources.md)
# A gene-level constraint SIGNAL: a low LOEUF means strong selection against
# loss-of-function, i.e. the gene is more likely essential/dosage-sensitive. Used
# as research evidence for prioritization, never as a clinical call. Pure client
# through http_post_json(); no {ellmer} imports. The variant-level gnomAD
# frequency lookup lives in R/tools/variant_effect.R.

GNOMAD_URL <- "https://gnomad.broadinstitute.org/api"
GNOMAD_WEB <- "https://gnomad.broadinstitute.org/gene"

GNOMAD_CONSTRAINT_QUERY <- paste(
  "query($sym: String!) {",
  "  gene(gene_symbol: $sym, reference_genome: GRCh38) {",
  "    gene_id",
  "    gnomad_constraint { oe_lof_upper pli }",
  "  }",
  "}",
  sep = "\n"
)

# LOEUF constraint for a gene symbol. Returns:
#   list(ok = TRUE, symbol, loeuf, pli, source_id, source_url)
#   list(ok = FALSE, error = "...")
# A gene with no constraint record (e.g. very short genes) is ok = FALSE, so it
# is treated as a missing annotation, not a spurious 0.
gnomad_loeuf <- function(symbol) {
  if (is_blank(symbol)) {
    return(list(ok = FALSE, error = "No gene symbol for gnomAD lookup."))
  }
  sym <- toupper(trimws(symbol))
  res <- http_post_json(
    GNOMAD_URL,
    body = list(
      query = GNOMAD_CONSTRAINT_QUERY,
      variables = list(sym = sym)
    ),
    source = "gnomAD"
  )
  if (!res$ok) {
    return(list(ok = FALSE, error = res$error))
  }
  if (!is.null(res$data$errors)) {
    return(list(ok = FALSE, error = "gnomAD returned a query error."))
  }
  gnomad_constraint_parse(res$data, sym)
}

# Pure parser: a gnomAD gene-constraint body -> the LOEUF signal. Separated from
# the fetch so it is testable offline against a JSON fixture.
gnomad_constraint_parse <- function(data, symbol) {
  gene <- pluck_at(data, "data", "gene")
  if (is.null(gene)) {
    return(list(
      ok = FALSE,
      error = paste0("gnomAD has no record for '", symbol, "'.")
    ))
  }
  con <- pluck_at(gene, "gnomad_constraint")
  loeuf <- suppressWarnings(as.numeric(
    pluck_at(con, "oe_lof_upper", default = NA)
  ))
  if (is.na(loeuf)) {
    return(list(
      ok = FALSE,
      error = paste0("gnomAD has no LOEUF for '", symbol, "'.")
    ))
  }
  pli <- suppressWarnings(as.numeric(pluck_at(con, "pli", default = NA)))
  gene_id <- pluck_at(gene, "gene_id", default = symbol)
  list(
    ok = TRUE,
    symbol = symbol,
    loeuf = loeuf,
    pli = pli,
    source_id = paste0("gnomAD:gene:", symbol, ":constraint"),
    source_url = paste0(GNOMAD_WEB, "/", gene_id, "?dataset=gnomad_r4")
  )
}

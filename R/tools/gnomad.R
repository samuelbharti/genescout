# gnomAD gene-constraint client - LOEUF (loss-of-function observed/expected upper
# bound). Endpoint: https://gnomad.broadinstitute.org/api (see docs/data_sources.md)
# A gene-level constraint SIGNAL: a low LOEUF means strong selection against
# loss-of-function, i.e. the gene is more likely essential/dosage-sensitive. Used
# as research evidence for prioritization, never as a clinical call. Pure client
# through http_post_json(); no {ellmer} imports. The variant-level gnomAD
# frequency lookup lives in R/tools/variant_effect.R.

GNOMAD_URL <- "https://gnomad.broadinstitute.org/api"
GNOMAD_WEB <- "https://gnomad.broadinstitute.org/gene"

# The gnomAD API takes one gene per query (batching is done with GraphQL aliases;
# here we query one gene at a time and rely on the shared HTTP cache). The symbol
# is inlined, so it is validated against a strict allow-list first to avoid any
# query injection.
gnomad_constraint_query <- function(symbol) {
  sprintf(
    paste0(
      "{ gene(gene_symbol: \"%s\", reference_genome: GRCh38) ",
      "{ gnomad_constraint { oe_lof_upper pli } } }"
    ),
    symbol
  )
}

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
  if (!grepl("^[A-Za-z0-9._-]+$", sym)) {
    return(list(
      ok = FALSE,
      error = paste0("Invalid gene symbol '", symbol, "'.")
    ))
  }
  res <- http_post_json(
    GNOMAD_URL,
    body = list(query = gnomad_constraint_query(sym)),
    source = "gnomAD"
  )
  err <- graphql_error(res, "gnomAD")
  if (!is.null(err)) {
    return(err)
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
  list(
    ok = TRUE,
    symbol = symbol,
    loeuf = loeuf,
    pli = pli,
    source_id = paste0("gnomAD:gene:", symbol, ":constraint"),
    source_url = paste0(GNOMAD_WEB, "/", symbol)
  )
}

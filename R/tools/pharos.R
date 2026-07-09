# Pharos client - Target Development Level (TDL).
# Endpoint: https://pharos-api.ncats.io/graphql  (see docs/data_sources.md)
# TDL is Pharos/IDG's tractability classification (Tclin > Tchem > Tbio > Tdark);
# used as a gene-level druggability / actionability SIGNAL for prioritization,
# never as a clinical call. Pure client through http_post_json(); no {ellmer}
# imports.

PHAROS_URL <- "https://pharos-api.ncats.io/graphql"
PHAROS_WEB <- "https://pharos.nih.gov/targets"

# TDL -> a 0-1 druggability score (already on a 0-1 scale, normalized by identity).
PHAROS_TDL_SCORE <- c(Tclin = 1.0, Tchem = 0.75, Tbio = 0.5, Tdark = 0.25)

PHAROS_QUERY <- "query($sym: String!) { target(q: { sym: $sym }) { sym tdl } }"

# TDL score for a gene symbol. Returns:
#   list(ok = TRUE, symbol, tdl, score, source_id, source_url)
#   list(ok = FALSE, error = "...")
pharos_tdl <- function(symbol) {
  if (is_blank(symbol)) {
    return(list(ok = FALSE, error = "No gene symbol for Pharos lookup."))
  }
  sym <- toupper(trimws(symbol))
  res <- http_post_json(
    PHAROS_URL,
    body = list(query = PHAROS_QUERY, variables = list(sym = sym)),
    source = "Pharos"
  )
  if (!res$ok) {
    return(list(ok = FALSE, error = res$error))
  }
  if (!is.null(res$data$errors)) {
    return(list(ok = FALSE, error = "Pharos returned a query error."))
  }
  pharos_tdl_parse(res$data, sym)
}

# Pure parser: a Pharos target body -> the TDL signal. Separated from the fetch
# so it is testable offline against a JSON fixture. An unknown/absent TDL is a
# miss (ok = FALSE).
pharos_tdl_parse <- function(data, symbol) {
  target <- pluck_at(data, "data", "target")
  if (is.null(target)) {
    return(list(
      ok = FALSE,
      error = paste0("Pharos has no record for '", symbol, "'.")
    ))
  }
  tdl <- as.character(pluck_at(target, "tdl", default = NA_character_))
  if (is_blank(tdl) || is.na(PHAROS_TDL_SCORE[tdl])) {
    return(list(
      ok = FALSE,
      error = paste0("Pharos has no known TDL for '", symbol, "'.")
    ))
  }
  list(
    ok = TRUE,
    symbol = symbol,
    tdl = tdl,
    score = unname(PHAROS_TDL_SCORE[tdl]),
    source_id = paste0("Pharos:gene:", symbol, ":", tdl),
    source_url = paste0(PHAROS_WEB, "/", symbol)
  )
}

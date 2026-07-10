# STRING protein-interaction client - within-list network connectivity.
# Endpoint: https://string-db.org/api  (see docs/data_sources.md)
# For a SET of candidate genes, how connected each gene is to the OTHER candidates
# in the same list via high-confidence STRING interactions - a "does this candidate
# sit inside a connected module with the rest of my list?" SIGNAL. This is
# COHORT-RELATIVE (a gene's value depends on which other genes are in the list), so
# it is used as an annotation that only nudges a connected gene up, never penalizes
# an isolated one, and never as primary evidence. Research evidence for
# prioritization, never a clinical call. Pure client through http_get_json(); no
# {ellmer} imports. The edge parser + connectivity math are pure, testable offline.

STRING_BASE <- "https://string-db.org/api"
STRING_WEB <- "https://string-db.org/cgi/network"
STRING_HUMAN <- 9606L
# required_score is 0-1000; 700 = combined score >= 0.7 (STRING's "high confidence").
STRING_MIN_SCORE <- 700L
# Cap identifiers per network call so the query URL stays bounded on a large seeded
# discovery set (which is itself capped upstream at ~200 genes).
STRING_MAX_NODES <- 500L

# The within-list interaction network for a set of gene symbols. Returns:
#   list(ok = TRUE, edges = tibble(gene_a, gene_b, score), n_query, source_id,
#        source_url)
#   list(ok = FALSE, error = "...")
# Fewer than two usable symbols is ok = FALSE (no network to compute).
string_network <- function(
  symbols,
  species = STRING_HUMAN,
  required_score = STRING_MIN_SCORE
) {
  syms <- toupper(trimws(as.character(symbols %||% character())))
  syms <- unique(syms[
    !is.na(syms) & nzchar(syms) & grepl("^[A-Za-z0-9._-]+$", syms)
  ])
  if (length(syms) < 2) {
    return(list(ok = FALSE, error = "Need >= 2 genes for a STRING network."))
  }
  if (length(syms) > STRING_MAX_NODES) {
    syms <- syms[seq_len(STRING_MAX_NODES)]
  }
  res <- http_get_json(
    STRING_BASE,
    path = "json/network",
    query = list(
      identifiers = paste(syms, collapse = "\r"),
      species = species,
      required_score = required_score
    ),
    source = "STRING"
  )
  if (!res$ok) {
    return(list(ok = FALSE, error = res$error))
  }
  list(
    ok = TRUE,
    edges = string_network_parse(res$data),
    n_query = length(syms),
    source_id = paste0("STRING:network:", species),
    source_url = paste0(
      STRING_WEB,
      "?identifiers=",
      paste(syms, collapse = "%0d"),
      "&species=",
      species
    )
  )
}

# Pure parser: a STRING network body (a JSON array of edges) -> tibble(gene_a,
# gene_b, score). `score` is STRING's combined score on a 0-1 scale. Separated from
# the fetch so it is testable offline against a recorded fixture.
string_network_parse <- function(data) {
  empty <- tibble::tibble(
    gene_a = character(),
    gene_b = character(),
    score = numeric()
  )
  if (is.null(data) || !is.list(data) || length(data) == 0) {
    return(empty)
  }
  a <- vapply(
    data,
    function(e) {
      toupper(as.character(pluck_at(e, "preferredName_A", default = NA)))
    },
    character(1)
  )
  b <- vapply(
    data,
    function(e) {
      toupper(as.character(pluck_at(e, "preferredName_B", default = NA)))
    },
    character(1)
  )
  s <- vapply(
    data,
    function(e) {
      suppressWarnings(as.numeric(pluck_at(e, "score", default = NA)))
    },
    numeric(1)
  )
  keep <- !is.na(a) & !is.na(b) & nzchar(a) & nzchar(b)
  tibble::tibble(gene_a = a[keep], gene_b = b[keep], score = s[keep])
}

# The within-list connectivity of each gene: how many DISTINCT other genes in
# `symbols` it shares a high-confidence STRING edge with. Pure so it is unit
# testable. `symbols` is the full candidate set (upper-cased), so an isolated gene
# is returned with degree 0 (not dropped). Returns tibble(symbol, degree,
# partners = list<chr>), one row per unique symbol.
string_connectivity <- function(edges, symbols, min_score = 0.7) {
  syms <- unique(toupper(trimws(as.character(symbols %||% character()))))
  syms <- syms[!is.na(syms) & nzchar(syms)]
  in_set <- function(x) x %in% syms
  partners <- stats::setNames(vector("list", length(syms)), syms)
  for (s in syms) {
    partners[[s]] <- character()
  }
  if (nrow(edges) > 0) {
    ok <- !is.na(edges$score) & edges$score >= min_score
    ea <- edges$gene_a[ok]
    eb <- edges$gene_b[ok]
    for (i in seq_along(ea)) {
      x <- ea[i]
      y <- eb[i]
      if (x == y || !in_set(x) || !in_set(y)) {
        next
      }
      partners[[x]] <- union(partners[[x]], y)
      partners[[y]] <- union(partners[[y]], x)
    }
  }
  tibble::tibble(
    symbol = syms,
    degree = vapply(syms, function(s) length(partners[[s]]), integer(1)),
    partners = unname(lapply(syms, function(s) sort(partners[[s]])))
  )
}

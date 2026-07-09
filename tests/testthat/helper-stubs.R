# Offline stubs for the enrichment / orchestration spine, shared across tests.
# A stub resolver stands in for MyGene; stub signals stand in for the source
# extractors, so the merge -> rank pipeline runs deterministically with no network.

stub_resolver <- function(symbol, species = "human") {
  map <- list(
    NF1 = list(id = "ENSG00000196712", sym = "NF1"),
    P53 = list(id = "ENSG00000141510", sym = "TP53"),
    TP53 = list(id = "ENSG00000141510", sym = "TP53")
  )
  hit <- map[[toupper(symbol)]]
  if (is.null(hit)) {
    return(list(ok = FALSE, error = "no match"))
  }
  list(ok = TRUE, symbol = hit$sym, ensembl_gene = hit$id, entrez = NA)
}

stub_signal <- function(key, values) {
  extractor <- function(resolved) {
    v <- values[[resolved$gene_id]]
    if (is.null(v)) {
      return(signal_miss())
    }
    list(
      ok = TRUE,
      raw = v,
      source_id = paste0("STUB:", resolved$gene_id),
      source_url = "https://example.org",
      evidence = evidence_long_rows(
        resolved$gene_id,
        key,
        "literature",
        "stub evidence",
        "",
        NA_real_,
        paste0("STUB:", resolved$gene_id),
        "https://example.org"
      )
    )
  }
  candid_signal(key, toupper(key), "Stub", extractor, normalize_identity, 1)
}

# Both genes present in both signals, but NF1 scores higher overall (composite
# 0.75 vs TP53 0.25), so the deterministic rank is unambiguous in tests.
stub_registry <- function() {
  list(
    stub_signal("a", list(ENSG00000196712 = 1.0, ENSG00000141510 = 0.5)),
    stub_signal("b", list(ENSG00000196712 = 0.5, ENSG00000141510 = 0.0))
  )
}

# MyGene.info client - symbol resolution.
# Endpoint: https://mygene.info  (see docs/data_sources.md)
# Resolves a gene symbol to stable identifiers (Ensembl / Entrez / UniProt).
# Pure client through http_get_json(); no {ellmer} imports.

# Resolve one symbol to a list of identifiers.
resolve_symbol <- function(symbol, species = "human") {
  not_implemented("resolve_symbol (MyGene.info)")
}

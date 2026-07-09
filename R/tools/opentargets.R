# Open Targets Platform client - gene/disease associations.
# Endpoint: https://api.platform.opentargets.org  (GraphQL; see docs/data_sources.md)
# Returns disease associations for a gene, each tagged with an Open Targets id so
# the citation gate can ground it. This is the Phase 0 vertical-slice client.
# Pure client through http_post_json(); no {ellmer} imports.

# Gene (Ensembl id or symbol) -> associated diseases with association scores.
gene_disease_assoc <- function(gene, size = 25) {
  not_implemented("gene_disease_assoc (Open Targets)")
}

# Pathway clients - Reactome and PAGER.
# Endpoints: https://reactome.org/ContentService ; PAGER (see docs/data_sources.md)
# Reactome gives pathway membership; PAGER gives pathway/gene-set enrichment.
# Pure clients through http_get_json(); no {ellmer} imports.

# Gene -> Reactome pathways it participates in.
reactome_pathways <- function(gene) {
  not_implemented("reactome_pathways (Reactome)")
}

# Gene set -> enriched pathways / gene sets (PAGER).
pager_enrichment <- function(genes) {
  not_implemented("pager_enrichment (PAGER)")
}

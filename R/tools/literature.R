# Literature clients - Europe PMC and PubTator.
# Endpoints (see docs/data_sources.md):
#   Europe PMC  https://www.ebi.ac.uk/europepmc/webservices/rest
#   PubTator    https://www.ncbi.nlm.nih.gov/research/pubtator3-api
# Europe PMC retrieves citations; PubTator supplies pre-annotated
# gene/disease/variant mentions. Every returned item carries a PMID/PMCID so the
# citation gate can ground it. Pure clients; no {ellmer} imports.

# Search Europe PMC for papers matching a query (gene + disease context).
europepmc_search <- function(query, limit = 25) {
  not_implemented("europepmc_search (Europe PMC)")
}

# Retrieve PubTator annotations (gene/disease/variant mentions) for PMIDs.
pubtator_annotations <- function(pmids) {
  not_implemented("pubtator_annotations (PubTator)")
}

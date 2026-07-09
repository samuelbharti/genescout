# Orchestration: the top-level gene-list prioritizer.
#
# Deterministic, gene-only, no LLM (the subjective-ranking agent is a later
# stage). For a set of gene lists:
#   flatten -> resolve to canonical ids (dedupe) -> enrich (per-source signals)
#   -> citation gate -> assemble the gene x signal matrix -> composite rank.
# The free-text `description` (what the user is studying) is carried through for
# the later agent stage; it does NOT drive the deterministic queries.
#
# Return shape:
#   list(
#     description        = <free text, for the agent stage>,
#     genes              = <ranked wide matrix: rank, symbol, per-signal raw+_n,
#                           composite, grade, resolved, input_lists, ...>,
#     signals            = <tidy long signals>,
#     evidence           = <gated evidence for drill-down>,
#     rejected           = <ungrounded evidence dropped by the gate>,
#     registry           = <signal registry summary for the UI legend>,
#     provenance         = <sources queried>,
#     generated_with_llm = FALSE
#   )

run_review <- function(
  gene_lists,
  description = "",
  config = NULL,
  registry = candid_signal_registry(),
  resolver = resolve_symbol,
  coverage_bonus = rubric_coverage_bonus()
) {
  flat <- flatten_gene_lists(as_gene_lists(gene_lists))
  if (nrow(flat) == 0) {
    stop("No genes to review.", call. = FALSE)
  }
  resolved <- resolve_genes(flat, resolver = resolver)
  enriched <- enrich_genes(resolved, registry)
  gated <- validate_evidence(enriched$evidence_long)

  genes <- assemble_matrix(enriched$signals_long, resolved, registry)
  genes <- compute_composite(genes, registry, coverage_bonus = coverage_bonus)
  genes <- rank_genes(genes)
  genes$grade <- grade_for_score(genes$composite)

  list(
    description = description %||% "",
    genes = genes,
    signals = enriched$signals_long,
    evidence = gated$kept,
    rejected = gated$rejected,
    registry = registry_summary(registry),
    provenance = candid_provenance(),
    generated_with_llm = FALSE
  )
}

# Coerce assorted inputs into the named list of character vectors that
# flatten_gene_lists() expects. Accepts a named list (passed through), a bare
# character vector (one list), or a candidate/gene data frame (its gene column).
as_gene_lists <- function(x) {
  if (is.data.frame(x)) {
    col <- intersect(c("gene", "candidate", "symbol"), names(x))[1]
    if (!is.na(col)) {
      return(list(input = as.character(x[[col]])))
    }
    return(list())
  }
  if (is.list(x)) {
    return(x)
  }
  if (is.character(x)) {
    return(list(input = x))
  }
  list()
}

# Provenance for the sources the deterministic pipeline queries.
candid_provenance <- function() {
  list(
    list(source = "MyGene.info", endpoint = MYGENE_BASE),
    list(source = "Open Targets Platform", endpoint = OPENTARGETS_URL),
    list(source = "Europe PMC", endpoint = EUROPEPMC_BASE),
    list(source = "ClinVar (NCBI E-utilities)", endpoint = CLINVAR_EUTILS_BASE)
  )
}

# TRUE when an LLM step can run: ellmer installed AND the configured provider's
# credentials are present. Reserved for the later subjective-ranking agent.
candid_llm_available <- function(config = load_config()) {
  requireNamespace("ellmer", quietly = TRUE) &&
    provider_credentials_ready(config$provider %||% "anthropic")
}

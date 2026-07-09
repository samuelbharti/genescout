# Orchestration: the top-level gene-list prioritizer.
#
# Deterministic, no LLM (the subjective-ranking agent is a later stage). Split in
# two so the UI can re-rank on a weight change without re-querying:
#   run_enrich(): flatten -> resolve to canonical ids (dedupe) -> enrich
#     (per-source signals) -> citation gate -> assemble the gene x signal matrix.
#   rank_result(): compute composite (with optional weight override) -> rank ->
#     grade. Pure and cheap.
# run_review() runs both for the CLI / evals / tests. The free-text `description`
# (what the user is studying) is carried through for the later agent stage.
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

# The network half: flatten -> resolve -> enrich -> citation gate -> assemble the
# (unranked) gene x signal matrix. Runs once per "Rank genes" click. `context`
# carries run-wide state (e.g. a resolved disease) for disease-aware extractors.
# The returned list keeps the full registry object (`registry_obj`) so the cheap
# ranking half can be recomputed with new weights without re-querying.
run_enrich <- function(
  gene_lists,
  description = "",
  config = NULL,
  registry = candid_signal_registry(),
  resolver = resolve_symbol,
  context = list()
) {
  flat <- flatten_gene_lists(as_gene_lists(gene_lists))
  if (nrow(flat) == 0) {
    stop("No genes to review.", call. = FALSE)
  }
  resolved <- resolve_genes(flat, resolver = resolver)
  enriched <- enrich_genes(resolved, registry, context = context)
  gated <- validate_evidence(enriched$evidence_long)
  genes <- assemble_matrix(enriched$signals_long, resolved, registry)

  list(
    description = description %||% "",
    genes = genes,
    signals = enriched$signals_long,
    evidence = gated$kept,
    rejected = gated$rejected,
    registry = registry_summary(registry),
    registry_obj = registry,
    provenance = candid_provenance(context),
    context = context
  )
}

# The ranking half (pure, no network): score -> rank -> grade. `weights` (a named
# key -> weight vector) overrides the registry weights, so the UI weight sliders
# re-rank instantly on the cached `enriched` result. Drops the internal
# `registry_obj` from the public result.
rank_result <- function(
  enriched,
  weights = NULL,
  coverage_bonus = FALSE,
  generated_with_llm = FALSE
) {
  registry <- enriched$registry_obj
  genes <- compute_composite(
    enriched$genes,
    registry,
    weights = weights,
    coverage_bonus = coverage_bonus
  )
  genes <- rank_genes(genes)
  genes$grade <- grade_for_score(genes$composite)

  out <- enriched
  out$genes <- genes
  out$registry_obj <- NULL
  out$generated_with_llm <- generated_with_llm
  out
}

# One-shot pipeline (enrich + rank) for the CLI, evals, and tests. The Shiny app
# calls run_enrich() once and rank_result() reactively so sliders re-rank without
# re-querying.
run_review <- function(
  gene_lists,
  description = "",
  config = NULL,
  registry = candid_signal_registry(),
  resolver = resolve_symbol,
  coverage_bonus = rubric_coverage_bonus(),
  context = list()
) {
  enriched <- run_enrich(
    gene_lists,
    description = description,
    config = config,
    registry = registry,
    resolver = resolver,
    context = context
  )
  rank_result(enriched, weights = NULL, coverage_bonus = coverage_bonus)
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

# Provenance for the sources the deterministic pipeline queries. `context` may
# carry a resolved disease (PR2 discovery mode), recorded here for the audit.
candid_provenance <- function(context = list()) {
  sources <- list(
    list(source = "MyGene.info", endpoint = MYGENE_BASE),
    list(source = "Open Targets Platform", endpoint = OPENTARGETS_URL),
    list(source = "Europe PMC", endpoint = EUROPEPMC_BASE),
    list(source = "ClinVar (NCBI E-utilities)", endpoint = CLINVAR_EUTILS_BASE),
    list(source = "DGIdb", endpoint = DGIDB_URL),
    list(source = "gnomAD", endpoint = GNOMAD_URL),
    list(source = "Pharos", endpoint = PHAROS_URL)
  )
  disease <- pluck_at(context, "disease")
  if (!is.null(disease) && !is_blank(disease$id)) {
    sources <- c(
      sources,
      list(list(
        source = paste0("Disease context: ", disease$name %||% disease$id),
        endpoint = disease$id
      ))
    )
  }
  sources
}

# TRUE when an LLM step can run: ellmer installed AND the configured provider's
# credentials are present. Reserved for the later subjective-ranking agent.
candid_llm_available <- function(config = load_config()) {
  requireNamespace("ellmer", quietly = TRUE) &&
    provider_credentials_ready(config$provider %||% "anthropic")
}

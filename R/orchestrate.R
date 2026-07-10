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
  context = list(),
  seeder = seed_disease_genes
) {
  cs <- as_candidate_set(gene_lists)
  # Optional disease-context priors (context/*.yaml: FLAGS genes, tissues, drivers)
  # for the caveats stage. Accept an already-loaded `priors` list or a `priors_id`
  # to load; a bad id degrades to no priors rather than crashing the run.
  if (is.null(context$priors) && !is_blank(pluck_at(context, "priors_id"))) {
    context$priors <- tryCatch(
      load_context(context$priors_id),
      error = function(e) NULL
    )
  }
  # Discovery: with a disease context, seed candidate genes from the disease-keyed
  # sources (union with the user's set) and stash their per-gene tables for the
  # disease-mode extractors. The seeded genes go in as their own candid_source
  # marked `seeded = TRUE` (id prefixed `seed:`), so a later stage can tell the
  # engine's own universe from the user's real sources. `seeder` is injectable.
  disease <- pluck_at(context, "disease")
  if (!is.null(disease)) {
    seeded <- seeder(disease)
    context$seed_data <- seeded$data
    if (length(seeded$symbols) > 0) {
      label <- paste0("disease: ", disease$name %||% disease$id)
      cs <- candidate_set_add(
        cs,
        candid_source(
          seeded$symbols,
          label = label,
          id = paste0("seed:disease:", disease$id %||% slugify(label)),
          type = "disease_seed",
          seeded = TRUE
        )
      )
    }
    # Record when the seeded universe was capped, so the truncation is audited in
    # the provenance rather than being a silent limit.
    n_seeded <- seeded$n_seeded %||% length(seeded$symbols)
    if (n_seeded > length(seeded$symbols)) {
      context$seed_capped <- list(
        kept = length(seeded$symbols),
        total = n_seeded
      )
    }
  }
  # Cross-source corroboration: the labels of the user's OWN (non-seeded) sources.
  # When the user gave >= 2, append the cross-source signal so a gene appearing in
  # more of their sources ranks higher. Captured from the `seeded` flag, so the
  # disease-discovery universe is never counted as user corroboration.
  user_sources <- vapply(
    Filter(function(s) !isTRUE(s$seeded), unclass(cs)),
    function(s) s$label,
    character(1)
  )
  context$user_sources <- user_sources
  registry_keys <- vapply(registry, function(s) s$key, character(1))
  if (length(user_sources) >= 2 && !("cross_source" %in% registry_keys)) {
    registry <- c(registry, list(cross_source_signal()))
  }

  flat <- flatten_candidate_set(cs)
  if (nrow(flat) == 0) {
    stop("No genes to review.", call. = FALSE)
  }
  resolved <- resolve_genes(flat, resolver = resolver)
  enriched <- enrich_genes(resolved, registry, context = context)
  # Fill the input-derived signals (cross_source) and fold their tidy rows +
  # grounded provenance evidence into the same tables the network signals produce.
  input_enr <- enrich_input_signals(resolved, registry, context = context)
  signals_long <- dplyr::bind_rows(
    enriched$signals_long,
    input_enr$signals_long
  )
  evidence_long <- dplyr::bind_rows(
    enriched$evidence_long,
    input_enr$evidence_long
  )
  gated <- validate_evidence(evidence_long)
  genes <- assemble_matrix(signals_long, resolved, registry)

  list(
    description = description %||% "",
    genes = genes,
    signals = signals_long,
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
  caveats = TRUE,
  generated_with_llm = FALSE
) {
  registry <- enriched$registry_obj
  genes <- compute_composite(
    enriched$genes,
    registry,
    weights = weights,
    coverage_bonus = coverage_bonus
  )
  # Caveats/veto: deterministic anti-bias override. Runs on the cheap ranking half
  # so a slider change re-applies it with no re-query; reads context$priors when a
  # disease context supplied them.
  genes <- apply_caveats(
    genes,
    registry,
    context = enriched$context %||% list(),
    enabled = isTRUE(caveats)
  )
  genes <- rank_genes(genes)
  genes$grade <- grade_for_score(genes$composite)
  if ("vetoed" %in% names(genes)) {
    vetoed <- as.logical(genes$vetoed)
    vetoed[is.na(vetoed)] <- FALSE
    genes$grade[vetoed] <- "Vetoed"
  }

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
  caveats = TRUE,
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
  rank_result(
    enriched,
    weights = NULL,
    coverage_bonus = coverage_bonus,
    caveats = caveats
  )
}

# Coerce assorted inputs into the named list of character vectors that
# flatten_gene_lists() expects. The canonical model is now a `candidate_set`
# (R/parse_input.R); this is a thin back-compat shim over it. Dispatch runs
# through as_candidate_set(), which keys on the candidate_set / candid_source S3
# classes FIRST - a candidate_set is itself a list, so the old bare
# `if (is.list(x)) return(x)` passthrough would have handed a list of
# candid_source records straight to flatten and corrupted the run.
as_gene_lists <- function(x) {
  candidate_set_to_named_lists(as_candidate_set(x))
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
    list(source = "Pharos", endpoint = PHAROS_URL),
    list(source = "Reactome", endpoint = REACTOME_BASE)
  )
  disease <- pluck_at(context, "disease")
  if (!is.null(disease) && !is_blank(disease$id)) {
    sources <- c(
      sources,
      list(
        list(
          source = "Genomics England PanelApp",
          endpoint = PANELAPP_BASE
        ),
        list(source = "DISEASES (Jensen Lab)", endpoint = DISEASES_BASE),
        list(
          source = paste0("Disease context: ", disease$name %||% disease$id),
          endpoint = disease$id
        )
      )
    )
  }
  priors <- pluck_at(context, "priors")
  if (!is.null(priors) && !is_blank(priors$label %||% priors$id)) {
    sources <- c(
      sources,
      list(list(
        source = paste0("Context priors: ", priors$label %||% priors$id),
        endpoint = ""
      ))
    )
  }
  cap <- pluck_at(context, "seed_capped")
  if (!is.null(cap)) {
    sources <- c(
      sources,
      list(list(
        source = sprintf(
          "Discovery seeding: kept top %d of %d seeded candidate genes",
          cap$kept,
          cap$total
        ),
        endpoint = ""
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

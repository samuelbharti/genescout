# Orchestration: the top-level pipeline entry point.
#
# For each candidate, fan out to three specialists (see R/evidence.R):
#   pathway-disease (Open Targets), literature (Europe PMC), and - when a variant
#   is supplied - variant-effect (Ensembl VEP / gnomAD / ClinVar). Their grounded
#   evidence is combined, run through the citation gate, scored/caveated against
#   the disease context, and assembled into a ranked review. When ellmer is
#   available and an API key is set, a short grounded narrative is added per
#   candidate; otherwise the deterministic evidence stands on its own.
#
# Return shape:
#   list(
#     context    = <context list>,
#     candidates = <list of per-candidate results>,
#     ranked     = <data.frame: symbol, grade, score, top_disease, n_evidence>,
#     provenance = <sources used>,
#     generated_with_llm = <logical>
#   )

run_review <- function(candidates, context, config = load_config()) {
  stopifnot(is.data.frame(candidates))
  if (nrow(candidates) == 0) {
    stop("No candidates to review.", call. = FALSE)
  }
  ctx <- if (is.character(context)) load_context(context) else context
  use_llm <- candid_llm_available()

  per <- lapply(seq_len(nrow(candidates)), function(i) {
    review_one_candidate(candidates[i, , drop = FALSE], ctx, config, use_llm)
  })

  list(
    context = ctx,
    candidates = per,
    ranked = build_ranked_table(per),
    provenance = candid_provenance(),
    generated_with_llm = use_llm
  )
}

# Review a single candidate row end to end: fan out the specialists, gate, score.
review_one_candidate <- function(row, context, config, use_llm) {
  gene <- row$gene %||% row$candidate
  variant <- row$variant

  specialists <- fan_out_specialists(gene, variant, context)
  evidence <- dplyr::bind_rows(
    specialists$pathway_disease$evidence,
    specialists$literature$evidence,
    specialists$variant_effect$evidence
  )
  symbol <- specialists$pathway_disease$symbol %||% gene
  gated <- validate_evidence(evidence)
  scored <- score_candidate(gated$kept, context, symbol = symbol)
  caveats <- apply_caveats(gated$kept, context, symbol = symbol)

  narrative <- NA_character_
  if (isTRUE(use_llm) && nrow(gated$kept) > 0) {
    narrative <- narrate_candidate(symbol, gated$kept, context, config)
  }

  list(
    candidate = row$candidate,
    symbol = symbol,
    gene = gene,
    ensembl_id = specialists$pathway_disease$ensembl_id,
    ok = nrow(gated$kept) > 0,
    error = if (nrow(gated$kept) == 0) {
      specialists$pathway_disease$error %||%
        "No grounded evidence was retrieved."
    } else {
      NULL
    },
    grade = scored$grade,
    score = scored$score,
    rationale = scored$rationale,
    evidence = gated$kept,
    rejected = gated$rejected,
    caveats = caveats,
    next_step = suggested_next_step(scored, context),
    narrative = narrative
  )
}

# Run the three specialists for one candidate. Sequential by default; the ellmer
# agent path (R/agents.R) fans the same tools out concurrently when enabled.
fan_out_specialists <- function(gene, variant, context) {
  list(
    pathway_disease = gather_pathway_disease(gene),
    literature = gather_literature(gene, context),
    variant_effect = gather_variant_effect(variant)
  )
}

# Build the ranked summary table, highest score first.
build_ranked_table <- function(per) {
  df <- data.frame(
    symbol = vapply(
      per,
      function(c) as.character(c$symbol %||% NA),
      character(1)
    ),
    grade = vapply(
      per,
      function(c) as.character(c$grade %||% NA),
      character(1)
    ),
    score = vapply(per, function(c) as.numeric(c$score %||% NA), numeric(1)),
    top_disease = vapply(per, candidate_top_disease, character(1)),
    n_evidence = vapply(
      per,
      function(c) {
        if (is.null(c$evidence)) 0L else nrow(c$evidence)
      },
      integer(1)
    ),
    caveats = vapply(
      per,
      function(c) {
        if (length(c$caveats) == 0) "" else paste(c$caveats, collapse = " ")
      },
      character(1)
    ),
    stringsAsFactors = FALSE
  )
  df[order(-df$score), , drop = FALSE]
}

# The top disease name for a candidate (highest-scoring association), or "-".
candidate_top_disease <- function(candidate) {
  ev <- candidate$evidence
  if (is.null(ev) || nrow(ev) == 0) {
    return("-")
  }
  assoc <- ev[ev$domain == "pathway-disease" & !is.na(ev$score), , drop = FALSE]
  if (nrow(assoc) == 0) {
    return("-")
  }
  as.character(assoc$title[which.max(assoc$score)])
}

# A minimal, honest next-step suggestion for Phase 0.
suggested_next_step <- function(scored, context) {
  if (identical(scored$grade, "Insufficient evidence")) {
    return(
      "Confirm the gene symbol and check for aliases; no associations were found."
    )
  }
  tissues <- context$tissues_of_interest %||% character()
  tissue <- if (length(tissues) > 0) tissues[[1]] else "the relevant tissue"
  sprintf(
    "Validate the top disease association in %s (e.g. expression / perturbation in a context model).",
    tissue
  )
}

# Provenance for the sources the pipeline can query.
candid_provenance <- function() {
  list(
    list(source = "MyGene.info", endpoint = MYGENE_BASE),
    list(source = "Open Targets Platform", endpoint = OPENTARGETS_URL),
    list(source = "Europe PMC", endpoint = EUROPEPMC_BASE),
    list(source = "Ensembl VEP", endpoint = ENSEMBL_BASE),
    list(source = "gnomAD", endpoint = GNOMAD_URL),
    list(source = "ClinVar (NCBI E-utilities)", endpoint = EUTILS_BASE)
  )
}

# TRUE when an LLM narrative can be generated (ellmer installed + key present).
candid_llm_available <- function() {
  requireNamespace("ellmer", quietly = TRUE) &&
    nzchar(Sys.getenv("ANTHROPIC_API_KEY"))
}

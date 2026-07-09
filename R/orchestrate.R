# Orchestration: the top-level pipeline entry point.
#
# Phase 0 vertical slice: for each candidate, fetch Open Targets gene/disease
# associations (grounded, each with a source id), run them through the citation
# gate, score/caveat them against the disease context, and assemble a ranked
# review. When ellmer is available and an API key is set, a short grounded
# narrative is added per candidate; otherwise the deterministic evidence stands
# on its own. Later phases add the parallel variant-effect and literature
# specialists (see PLAN.md).
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

# Review a single candidate row end to end.
review_one_candidate <- function(row, context, config, use_llm) {
  gene <- row$gene %||% row$candidate
  assoc <- gene_disease_assoc(gene)

  if (!isTRUE(assoc$ok)) {
    return(list(
      candidate = row$candidate,
      symbol = gene,
      gene = gene,
      ok = FALSE,
      error = assoc$error,
      grade = "Insufficient evidence",
      score = 0,
      evidence = NULL,
      caveats = "No grounded evidence could be retrieved.",
      narrative = NA_character_
    ))
  }

  gated <- validate_evidence(assoc$evidence)
  scored <- score_candidate(gated$kept, context, symbol = assoc$symbol)
  caveats <- apply_caveats(gated$kept, context, symbol = assoc$symbol)

  narrative <- NA_character_
  if (isTRUE(use_llm)) {
    narrative <- narrate_candidate(assoc$symbol, gated$kept, context, config)
  }

  list(
    candidate = row$candidate,
    symbol = assoc$symbol,
    gene = gene,
    ensembl_id = assoc$ensembl_id,
    ok = TRUE,
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

# The top disease name for a candidate, or "-" if none.
candidate_top_disease <- function(candidate) {
  ev <- candidate$evidence
  if (is.null(ev) || nrow(ev) == 0) {
    return("-")
  }
  as.character(ev$disease[which.max(ev$score)])
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

# Provenance for the sources used in this slice.
candid_provenance <- function() {
  list(
    list(source = "MyGene.info", endpoint = MYGENE_BASE),
    list(source = "Open Targets Platform", endpoint = OPENTARGETS_URL)
  )
}

# TRUE when an LLM narrative can be generated (ellmer installed + key present).
candid_llm_available <- function() {
  requireNamespace("ellmer", quietly = TRUE) &&
    nzchar(Sys.getenv("ANTHROPIC_API_KEY"))
}

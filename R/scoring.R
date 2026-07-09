# Scoring and caveats. Phase 0 uses a light, transparent scheme over the Open
# Targets evidence; later phases combine multi-source evidence and the full
# caveats/veto logic (see prompts/scoring-rubric.md). Kept deterministic so the
# ranking is reproducible and testable.

# Grade thresholds on the best available association score (0-1).
CANDID_GRADE_BREAKS <- c(high = 0.5, moderate = 0.2)

# Score one candidate from its (already gated) multi-domain evidence + context
# priors. Grade is driven by the best Open Targets association score;
# literature and variant-effect items are counted as supporting evidence.
# Returns list(score, grade, rationale, is_driver). `evidence` is the kept
# normalized evidence tibble (see R/evidence.R).
score_candidate <- function(evidence, context, symbol = NA_character_) {
  drivers <- toupper(as.character(context$known_drivers %||% character()))
  is_driver <- !is.na(symbol) && toupper(symbol) %in% drivers

  if (is.null(evidence) || nrow(evidence) == 0) {
    return(list(
      score = 0,
      grade = "Insufficient evidence",
      rationale = "No grounded evidence was returned.",
      is_driver = is_driver
    ))
  }
  n_lit <- sum(evidence$domain == "literature")
  n_var <- sum(evidence$domain == "variant-effect")
  assoc <- evidence[
    evidence$domain == "pathway-disease" & !is.na(evidence$score),
    ,
    drop = FALSE
  ]

  if (nrow(assoc) == 0) {
    grade <- if (n_lit + n_var > 0) "Low" else "Insufficient evidence"
    return(list(
      score = 0,
      grade = grade,
      rationale = sprintf(
        "No disease-association score; %d paper(s) and %d variant item(s).",
        n_lit,
        n_var
      ),
      is_driver = is_driver
    ))
  }
  best <- max(assoc$score)
  rationale <- sprintf(
    "Top association score %.2f across %d disease(s); %d paper(s), %d variant item(s)%s.",
    best,
    nrow(assoc),
    n_lit,
    n_var,
    if (is_driver) "; known driver in this context" else ""
  )
  list(
    score = best,
    grade = grade_for_score(best),
    rationale = rationale,
    is_driver = is_driver
  )
}

# Map a numeric association score to a plausibility grade.
grade_for_score <- function(score) {
  if (is.na(score)) {
    return("Insufficient evidence")
  }
  if (score >= CANDID_GRADE_BREAKS[["high"]]) {
    "High"
  } else if (score >= CANDID_GRADE_BREAKS[["moderate"]]) {
    "Moderate"
  } else {
    "Low"
  }
}

# Caveats / anti-bias stage. Phase 0 flags the FLAGS/artifact genes from the
# context; the full down-rank/veto logic (gnomAD-common, unrelated-tissue-only,
# single-weak-source) lands with the variant-effect and literature specialists.
# Returns a character vector of caveat strings (possibly empty).
apply_caveats <- function(evidence, context, symbol = NA_character_) {
  caveats <- character()
  flags <- toupper(as.character(context$flags_genes %||% character()))
  if (!is.na(symbol) && toupper(symbol) %in% flags) {
    caveats <- c(
      caveats,
      "Listed among recurrent-artifact (FLAGS) genes for this context; treat with caution."
    )
  }
  if (!is.null(evidence) && nrow(evidence) == 1) {
    caveats <- c(
      caveats,
      "Supported by a single association; corroborate with other evidence."
    )
  }
  caveats
}

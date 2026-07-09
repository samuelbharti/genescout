# Scoring and caveats. Combines gated evidence with the disease-context priors
# into a per-candidate plausibility score, then runs the caveats/bias stage that
# can down-rank or veto a candidate. The rubric lives in prompts/scoring-rubric.md
# so the mapping is explicit and reviewable, not buried in code.

# Score one candidate from its (already gated) evidence + context priors.
# Returns list(score, grade, rationale).
score_candidate <- function(candidate_evidence, context) {
  not_implemented("score_candidate")
}

# Caveats / anti-bias stage. Down-ranks or vetoes candidates that look
# compelling but are: common in gnomAD, supported only by unrelated-tissue
# evidence, backed by a single weak source, or a known artifact/FLAGS gene.
# Records the reason on each affected candidate.
apply_caveats <- function(scored, context) {
  not_implemented("apply_caveats (down-rank / veto)")
}

# Orchestration: the top-level pipeline entry point. Given a parsed candidate
# tibble and a disease context, fan out the three specialists concurrently
# (ellmer parallel_chat_structured), gate their evidence on citations, score with
# context priors, apply caveats/veto, and return an assembled review result.
#
# Return shape (once implemented):
#   list(
#     context    = <context list>,
#     candidates = <list of per-candidate evidence + score + caveats>,
#     ranked     = <data frame: candidate, score, grade, caveats>,
#     provenance = <sources + versions used>
#   )

run_review <- function(candidates, context, config = load_config()) {
  stopifnot(is.data.frame(candidates))
  ctx <- if (is.character(context)) load_context(context) else context

  # Phase 1+: build_specialist() x3 -> parallel_chat_structured() over
  # `candidates`, then validate_evidence(), score_candidates(), apply_caveats(),
  # and assemble. Stubbed until the vertical slice lands.
  not_implemented("run_review (parallel specialist fan-out)")
}

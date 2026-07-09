# Agents (ellmer). Phase 0 uses a single grounded-narrative helper; the parallel
# variant-effect / pathway-disease / literature specialists and their
# type_object() evidence schemas land in Phase 1 (see PLAN.md). Provider/model
# come from config (never hardcoded); "any provider" is a config change.
#
# Everything here is guarded: if {ellmer} is not installed or no API key is set,
# the pipeline runs deterministically without a narrative.

# Roles -> which tool clients they may call. The specialist only ever sees its
# own allowlist, keeping contexts isolated (used in Phase 1).
specialist_tools <- list(
  `variant-effect` = c("vep_consequence", "gnomad_frequency", "clinvar_lookup"),
  `pathway-disease` = c(
    "gene_disease_assoc",
    "reactome_pathways",
    "pager_enrichment"
  ),
  literature = c("europepmc_search", "pubtator_annotations")
)

# Build an ellmer Chat for a role, using the model from config and the matching
# system prompt from prompts/. Kept thin so provider swaps are config-only.
candid_chat <- function(
  role_prompt,
  model_role = "specialist",
  config = load_config()
) {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    stop("The 'ellmer' package is required for LLM narration.", call. = FALSE)
  }
  ellmer::chat_anthropic(
    model = model_for(model_role, config),
    system_prompt = read_prompt(role_prompt)
  )
}

# Produce a short, grounded narrative for a candidate from its evidence. The
# prompt is constrained to the supplied evidence (each line carries a source id),
# so the model summarizes rather than recalls. Returns NA_character_ on any
# failure, so narration never breaks a review.
narrate_candidate <- function(
  symbol,
  evidence,
  context,
  config = load_config()
) {
  if (is.null(evidence) || nrow(evidence) == 0) {
    return(NA_character_)
  }
  tryCatch(
    {
      chat <- candid_chat("pathway-disease", "specialist", config)
      chat$chat(build_narrative_prompt(symbol, evidence, context))
    },
    error = function(e) NA_character_
  )
}

# Assemble the grounding prompt: only the retrieved associations, each with its
# Open Targets source id, plus the disease context label.
build_narrative_prompt <- function(symbol, evidence, context) {
  lines <- sprintf(
    "- %s (score %.2f) [source: %s]",
    evidence$disease,
    evidence$score,
    evidence$source_id
  )
  paste0(
    "Disease context: ",
    context$label %||% context$id %||% "unspecified",
    ".\n",
    "Gene: ",
    symbol,
    ".\n",
    "Open Targets associations (the ONLY evidence you may use):\n",
    paste(lines, collapse = "\n"),
    "\n\nIn 2-3 sentences, summarize how plausibly this gene relates to the ",
    "context, citing the diseases above. Do not introduce any fact not listed. ",
    "If support is weak or off-context, say so."
  )
}

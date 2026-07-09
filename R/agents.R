# Agents (ellmer). The three specialists gather grounded evidence deterministically
# in R/orchestrate.R (fan_out_specialists); this file adds the LLM layer: a
# grounded per-candidate narrative. Provider/model come from config (never
# hardcoded); "any provider" is a config change.
#
# Everything here is guarded: if {ellmer} is not installed or no API key is set,
# the pipeline runs deterministically without a narrative. An agentic path that
# registers these tools and fans them out with ellmer::parallel_chat_structured()
# is the planned enhancement; the allowlist below is its contract.

# Roles -> which tool clients they may call. The specialist only ever sees its
# own allowlist, keeping contexts isolated.
specialist_tools <- list(
  `variant-effect` = c("vep_consequence", "gnomad_frequency", "clinvar_lookup"),
  `pathway-disease` = c("gene_disease_assoc"),
  literature = c("europepmc_search")
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

# Assemble the grounding prompt: only the retrieved evidence rows (across all
# domains), each with its source id, plus the disease context label.
build_narrative_prompt <- function(symbol, evidence, context) {
  detail <- ifelse(
    is.na(evidence$detail) | !nzchar(evidence$detail),
    "",
    paste0(" - ", evidence$detail)
  )
  lines <- sprintf(
    "- [%s] %s%s [source: %s]",
    evidence$domain,
    evidence$title,
    detail,
    evidence$source_id
  )
  paste0(
    "Disease context: ",
    context$label %||% context$id %||% "unspecified",
    ".\n",
    "Gene: ",
    symbol,
    ".\n",
    "Grounded evidence (the ONLY evidence you may use):\n",
    paste(lines, collapse = "\n"),
    "\n\nIn 2-3 sentences, summarize how plausibly this gene relates to the ",
    "context, citing the evidence above. Do not introduce any fact not listed. ",
    "If support is weak or off-context, say so."
  )
}

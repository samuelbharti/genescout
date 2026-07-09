# Agents (ellmer) - the LLM layer, reserved for the Phase 2 subjective-ranking
# agent that re-ranks/filters the deterministic gene_matrix to a usable 20-100.
# The deterministic pipeline (R/orchestrate.R) uses NO LLM; nothing here runs
# until that stage lands. Provider/model come from config (never hardcoded), so
# switching providers is a config change.
#
# Live pieces used today: build_chat() + provider_credentials_ready(), which back
# candid_llm_available(). The narrate_* helpers and the specialist_tools allowlist
# are scaffolding for the agent stage. Everything is guarded: if {ellmer} is not
# installed or no credentials are set, the app runs deterministically.

# Roles -> which tool clients they may call. The specialist only ever sees its
# own allowlist, keeping contexts isolated.
specialist_tools <- list(
  `variant-effect` = c("vep_consequence", "gnomad_frequency", "clinvar_lookup"),
  `pathway-disease` = c("gene_disease_assoc"),
  literature = c("europepmc_search")
)

# Build an ellmer Chat for a role, using the provider + model from config and the
# matching system prompt from prompts/. Kept thin so provider swaps are config-only.
candid_chat <- function(
  role_prompt,
  model_role = "specialist",
  config = load_config()
) {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    stop("The 'ellmer' package is required for LLM narration.", call. = FALSE)
  }
  build_chat(
    provider = config$provider %||% "anthropic",
    model = model_for(model_role, config),
    system_prompt = read_prompt(role_prompt)
  )
}

# Map the configured provider to its ellmer constructor. Credentials come from
# the environment (see .Renviron.example), never from config. Adding a provider
# is a new case here plus its credential env var in provider_credentials_ready();
# the rest of the engine is untouched.
build_chat <- function(provider, model, system_prompt) {
  switch(
    provider,
    anthropic = ellmer::chat_anthropic(
      model = model,
      system_prompt = system_prompt
    ),
    google_gemini = ellmer::chat_google_gemini(
      model = model,
      system_prompt = system_prompt
    ),
    google_vertex = ellmer::chat_google_vertex(
      model = model,
      system_prompt = system_prompt
    ),
    stop(
      sprintf(
        paste0(
          "Unsupported provider '%s' in config.yml ",
          "(use anthropic, google_gemini, or google_vertex)."
        ),
        provider
      ),
      call. = FALSE
    )
  )
}

# Does the environment carry the credentials the given provider needs? A presence
# check only (nonblank env vars), not a live auth test. Vertex uses Application
# Default Credentials, so we gate on project + region being set; the actual ADC
# token (service-account JSON or `gcloud auth application-default login`) is
# resolved by ellmer/gargle at call time.
provider_credentials_ready <- function(provider) {
  switch(
    provider,
    anthropic = nzchar(Sys.getenv("ANTHROPIC_API_KEY")),
    google_gemini = nzchar(Sys.getenv("GEMINI_API_KEY")) ||
      nzchar(Sys.getenv("GOOGLE_API_KEY")),
    google_vertex = nzchar(Sys.getenv("GOOGLE_CLOUD_PROJECT")) &&
      nzchar(Sys.getenv("GOOGLE_CLOUD_LOCATION")),
    FALSE
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

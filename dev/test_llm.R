#!/usr/bin/env Rscript
# Live check that the configured LLM provider + credentials actually work. Reads the
# provider/model from config.yml and the credentials from your .Renviron (R loads it
# at startup), builds a chat for the orchestrator role, and sends a one-word ping.
#
#   Rscript dev/test_llm.R
#
# A 200 with a reply means your key/credentials and model are good. A 401/403 means the
# credentials are wrong for that provider's endpoint (e.g. an API key against Vertex,
# which requires OAuth - see .Renviron.example). Makes ONE real API call.

source("global.R")

provider <- candid_config$provider %||% "(unset)"
model <- tryCatch(
  model_for("orchestrator", candid_config),
  error = function(e) "(unset)"
)
cat(sprintf("provider: %s\nmodel:    %s\n", provider, model))

if (!provider_credentials_ready(provider)) {
  cat(sprintf(
    "\nCredentials for '%s' are NOT set in the environment. Fill .Renviron:\n%s\n",
    provider,
    switch(
      provider,
      google_gemini = "  GEMINI_API_KEY=...   (Gemini Developer API key)",
      google_vertex = "  GOOGLE_CLOUD_PROJECT=... GOOGLE_CLOUD_LOCATION=... + `gcloud auth application-default login` (OAuth, not an API key)",
      anthropic = "  ANTHROPIC_API_KEY=...",
      openai = "  OPENAI_API_KEY=...",
      "  (see .Renviron.example)"
    )
  ))
  quit(status = 1L)
}

cat("credentials: present\nsending a ping...\n\n")
out <- tryCatch(
  {
    chat <- build_chat(
      provider,
      model,
      "You are terse. Reply with a single word."
    )
    chat$chat("Reply with the word: OK")
  },
  error = function(e) {
    cat("REQUEST FAILED:\n", conditionMessage(e), "\n")
    quit(status = 1L)
  }
)
cat("reply:", paste(out, collapse = " "), "\n\nLLM PROVIDER OK\n")

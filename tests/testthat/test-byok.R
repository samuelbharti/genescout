# BYOK credential layer (R/byok.R) - offline unit tests. No network, no live keys:
# credentials are plain lists and the model maps come from config.yml. Tests run
# with the CWD at tests/testthat, so functions that read config.yml by its default
# path are exercised under GENESCOUT_APP_ROOT pointed at the app root (matching how the
# Shiny app and the offload daemon resolve it).

byok_app_root <- normalizePath(test_path("..", ".."))
byok_config_path <- file.path(byok_app_root, "config.yml")

test_that("genescout_byok_providers/meta/choices cover the three key providers", {
  provs <- genescout_byok_providers()
  expect_setequal(provs, c("anthropic", "google_gemini", "openai"))
  # Vertex is OAuth (ADC), not a pasteable key, so it is never offered for BYOK.
  expect_false("google_vertex" %in% provs)
  for (p in provs) {
    meta <- genescout_provider_meta(p)
    expect_true(nzchar(meta$label))
    expect_match(meta$key_url, "^https://")
    expect_true(nzchar(meta$env))
  }
  ch <- genescout_provider_choices()
  expect_length(ch, 3)
  expect_setequal(unname(ch), provs)
  expect_true(all(nzchar(names(ch)))) # human labels
})

test_that("genescout_default_byok_provider prefers a BYOK-capable configured provider", {
  expect_equal(
    genescout_default_byok_provider(list(provider = "openai")),
    "openai"
  )
  expect_equal(
    genescout_default_byok_provider(list(provider = "anthropic")),
    "anthropic"
  )
  # google_vertex is not a BYOK provider -> fall back to the first offered.
  expect_equal(
    genescout_default_byok_provider(list(provider = "google_vertex")),
    genescout_byok_providers()[1]
  )
  expect_equal(
    genescout_default_byok_provider(list()),
    genescout_byok_providers()[1]
  )
})

test_that("load_byok_models exposes tiered roles + a chat model per provider", {
  roles <- c("orchestrator", "caveats", "specialist", "input_curator", "chat")
  for (p in genescout_byok_providers()) {
    m <- load_byok_models(p, byok_config_path)
    expect_true(all(roles %in% names(m)), info = p)
    ok <- vapply(m[roles], function(x) is.character(x) && nzchar(x), logical(1))
    expect_true(all(ok), info = p)
  }
  expect_error(load_byok_models("nope", byok_config_path), "No BYOK model map")
})

test_that("genescout_provider_model_suggestions are unique, non-empty, from config", {
  withr::with_envvar(c(GENESCOUT_APP_ROOT = byok_app_root), {
    s <- genescout_provider_model_suggestions("anthropic")
    expect_gte(length(s), 1)
    expect_equal(s, unique(s))
    expect_true(all(nzchar(s)))
  })
})

test_that("genescout_byok_credential trims the key and blanks an empty model to NULL", {
  cr <- genescout_byok_credential("anthropic", "  sk-abc  ", model = "  ")
  expect_equal(cr$provider, "anthropic")
  expect_equal(cr$api_key, "sk-abc")
  expect_null(cr$model)
  expect_equal(
    genescout_byok_credential("openai", "k", model = "gpt-x")$model,
    "gpt-x"
  )
})

test_that("genescout_credential_ready reflects a usable key", {
  expect_false(genescout_credential_ready(NULL))
  expect_false(genescout_credential_ready(genescout_byok_credential(
    "openai",
    ""
  )))
  expect_true(genescout_credential_ready(genescout_byok_credential(
    "openai",
    "k"
  )))
})

test_that("byok_effective_config leaves the base config untouched without a key", {
  base <- list(
    provider = "google_vertex",
    models = list(orchestrator = "m"),
    sources = c("a", "b")
  )
  expect_identical(byok_effective_config(base, NULL), base)
  expect_identical(
    byok_effective_config(base, genescout_byok_credential("openai", "")),
    base
  )
})

test_that("byok_effective_config folds provider/models/api_key onto the base", {
  withr::with_envvar(c(GENESCOUT_APP_ROOT = byok_app_root), {
    base <- list(
      provider = "google_vertex",
      models = list(orchestrator = "old"),
      sources = c("x")
    )
    eff <- byok_effective_config(
      base,
      genescout_byok_credential("anthropic", "sk-1")
    )
    expect_equal(eff$provider, "anthropic")
    expect_equal(eff$api_key, "sk-1")
    expect_equal(eff$sources, c("x")) # base fields preserved
    expect_true(all(
      c("orchestrator", "specialist", "chat") %in% names(eff$models)
    ))
    expect_equal(
      model_for("orchestrator", eff),
      load_byok_models("anthropic")$orchestrator
    )
  })
})

test_that("a single-model override supersedes every role and the chat model", {
  withr::with_envvar(c(GENESCOUT_APP_ROOT = byok_app_root), {
    cr <- genescout_byok_credential("openai", "k", model = "gpt-mine")
    eff <- byok_effective_config(list(), cr)
    expect_true(all(unlist(eff$models) == "gpt-mine"))
    expect_equal(genescout_chat_model(cr), "gpt-mine")
  })
})

test_that("genescout_chat_model falls back to the provider's configured chat model", {
  withr::with_envvar(c(GENESCOUT_APP_ROOT = byok_app_root), {
    expect_equal(
      genescout_chat_model(genescout_byok_credential("google_gemini", "k")),
      load_byok_models("google_gemini")$chat
    )
  })
})

test_that("provider_credentials_ready: a BYOK key satisfies the check regardless of env", {
  withr::with_envvar(c(ANTHROPIC_API_KEY = ""), {
    expect_false(provider_credentials_ready("anthropic"))
    expect_true(provider_credentials_ready("anthropic", "sk-live"))
  })
  withr::with_envvar(c(OPENAI_API_KEY = "env-key"), {
    expect_true(provider_credentials_ready("openai"))
  })
})

test_that("genescout_llm_available reads a session api_key on the config", {
  skip_if_not_installed("ellmer")
  withr::with_envvar(c(ANTHROPIC_API_KEY = ""), {
    expect_false(genescout_llm_available(list(provider = "anthropic")))
    expect_true(genescout_llm_available(list(
      provider = "anthropic",
      api_key = "sk-live"
    )))
  })
})

test_that("genescout_redact_secret removes the literal key and is a no-op when empty", {
  expect_equal(
    genescout_redact_secret("boom sk-123 fail", "sk-123"),
    "boom <redacted-key> fail"
  )
  expect_equal(genescout_redact_secret("nothing here", ""), "nothing here")
  expect_equal(genescout_redact_secret(c("a", "b"), ""), "a b")
})

test_that("genescout_chat_grounding degrades gracefully with no run", {
  expect_match(genescout_chat_grounding(NULL), "No review has been run")
  expect_match(
    genescout_chat_grounding(list(genes = data.frame())),
    "No review has been run"
  )
})

test_that("genescout_chat_grounding summarizes the current run with grades", {
  genes <- data.frame(
    symbol = c("NF1", "TTN"),
    composite = c(0.62, 0.05),
    rank = c(1, 2),
    stringsAsFactors = FALSE
  )
  res <- list(genes = genes, context = list(label = "NF1-associated MPNST"))
  txt <- genescout_chat_grounding(res)
  expect_match(txt, "NF1")
  expect_match(txt, "TTN")
  expect_match(txt, "NF1-associated MPNST", fixed = TRUE)
  expect_match(txt, "High") # 0.62 -> High
  expect_match(txt, "2 genes ranked", fixed = TRUE)
})

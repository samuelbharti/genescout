# Provider selection + credential detection - offline (no ellmer, no network).
# Confirms "switching provider is a config change": the dispatch and the
# availability gate key off config$provider and the matching env vars.

test_that("provider_credentials_ready() detects each provider's env vars", {
  # Clear every accepted name (incl. the VERTEX_* aliases) so a developer's real
  # .Renviron - loaded when tests run from the app root - can't make a check pass.
  withr::local_envvar(c(
    ANTHROPIC_API_KEY = "",
    GEMINI_API_KEY = "",
    GOOGLE_API_KEY = "",
    OPENAI_API_KEY = "",
    GOOGLE_CLOUD_PROJECT = "",
    GOOGLE_CLOUD_LOCATION = "",
    VERTEX_PROJECT_ID = "",
    VERTEX_LOCATION = ""
  ))
  expect_false(provider_credentials_ready("anthropic"))
  expect_false(provider_credentials_ready("google_gemini"))
  expect_false(provider_credentials_ready("google_vertex"))
  expect_false(provider_credentials_ready("openai"))

  withr::local_envvar(c(ANTHROPIC_API_KEY = "sk-test"))
  expect_true(provider_credentials_ready("anthropic"))

  withr::local_envvar(c(OPENAI_API_KEY = "sk-openai-test"))
  expect_true(provider_credentials_ready("openai"))

  withr::local_envvar(c(GEMINI_API_KEY = "AIza-test"))
  expect_true(provider_credentials_ready("google_gemini"))

  withr::local_envvar(c(
    GOOGLE_CLOUD_PROJECT = "my-project",
    GOOGLE_CLOUD_LOCATION = "us-central1"
  ))
  expect_true(provider_credentials_ready("google_vertex"))
})

test_that("google_vertex requires BOTH project and location", {
  withr::local_envvar(c(
    VERTEX_PROJECT_ID = "",
    VERTEX_LOCATION = "",
    GOOGLE_CLOUD_PROJECT = "my-project",
    GOOGLE_CLOUD_LOCATION = ""
  ))
  expect_false(provider_credentials_ready("google_vertex"))
})

test_that("google_gemini accepts GOOGLE_API_KEY as an alias for GEMINI_API_KEY", {
  withr::local_envvar(c(GEMINI_API_KEY = "", GOOGLE_API_KEY = "AIza-alias"))
  expect_true(provider_credentials_ready("google_gemini"))
})

test_that("Vertex reads VERTEX_* first, then GOOGLE_CLOUD_* as aliases", {
  withr::local_envvar(c(
    VERTEX_PROJECT_ID = "",
    VERTEX_LOCATION = "",
    GOOGLE_CLOUD_PROJECT = "",
    GOOGLE_CLOUD_LOCATION = ""
  ))
  expect_false(provider_credentials_ready("google_vertex"))

  # The Google-standard names still work (back-compat).
  withr::with_envvar(
    c(GOOGLE_CLOUD_PROJECT = "proj-g", GOOGLE_CLOUD_LOCATION = "us-central1"),
    {
      expect_equal(vertex_project_id(), "proj-g")
      expect_equal(vertex_location(), "us-central1")
      expect_true(provider_credentials_ready("google_vertex"))
    }
  )

  # ellmer's VERTEX_* names win when both are set.
  withr::with_envvar(
    c(
      VERTEX_PROJECT_ID = "proj-v",
      GOOGLE_CLOUD_PROJECT = "proj-g",
      VERTEX_LOCATION = "europe-west1",
      GOOGLE_CLOUD_LOCATION = "us-central1"
    ),
    {
      expect_equal(vertex_project_id(), "proj-v")
      expect_equal(vertex_location(), "europe-west1")
    }
  )
})

test_that("an unknown provider is never ready", {
  expect_false(provider_credentials_ready("bogus"))
})

test_that("build_chat() rejects an unknown provider before any API call", {
  expect_error(
    build_chat("bogus", "some-model", "a prompt"),
    "Unsupported provider"
  )
})

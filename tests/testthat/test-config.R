# Config loader - profile/role resolution + app-path helper (offline).

# Tests run with the CWD at tests/testthat, so reach the app-root config by path.
config_path <- function() test_path("..", "..", "config.yml")

test_that("load_config() errors clearly on a missing file or profile", {
  expect_error(load_config("does-not-exist.yml"), "Config file not found")
  # The real config.yml exists but has no such profile.
  expect_error(
    load_config(config_path(), profile = "no-such-profile"),
    "Config profile not found"
  )
})

test_that("load_config() returns the active profile with a model map", {
  cfg <- load_config(config_path())
  expect_true(is.list(cfg))
  expect_false(is.null(cfg$models))
})

test_that("model_for() resolves a role or errors when it is absent", {
  cfg <- list(models = list(orchestrator = "m-big", specialist = "m-fast"))
  expect_equal(model_for("orchestrator", cfg), "m-big")
  expect_equal(model_for("specialist", cfg), "m-fast")
  expect_error(model_for("nonexistent", cfg), "No model configured for role")
})

test_that("candid_app_path() honors CANDID_APP_ROOT, else stays relative", {
  withr::with_envvar(c(CANDID_APP_ROOT = ""), {
    expect_equal(candid_app_path("rubric.yml"), "rubric.yml")
  })
  withr::with_envvar(c(CANDID_APP_ROOT = "/srv/app"), {
    expect_equal(
      candid_app_path("rubric.yml"),
      file.path("/srv/app", "rubric.yml")
    )
  })
})

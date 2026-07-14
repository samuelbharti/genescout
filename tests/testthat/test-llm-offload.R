# Crash-safe LLM offload - gating + in-process fallback (offline). The background
# daemon path (which spawns a worker and sources the engine) is verified by
# dev/smoke_parallel.R-style live checks, NOT here: the suite stays serial and never
# spawns a worker, so these tests exercise only the pass-through/fallback behavior.

test_that("genescout_llm_offload_available() is off under testthat", {
  # testthat sets TESTTHAT=true, the hard off-switch, so the suite never offloads.
  expect_false(genescout_llm_offload_available())
})

test_that("genescout_llm_run() is a pass-through when offloading is off", {
  # Same result, arguments forwarded verbatim (positional and named).
  expect_equal(genescout_llm_run(function(a, b) a + b, 40, 2), 42)
  scale_by <- function(x, scale = 1) x * scale
  expect_equal(genescout_llm_run(scale_by, 21, scale = 2), 42)
})

test_that("genescout_llm_run() honors the opt-out option without spawning a worker", {
  withr::with_envvar(c(TESTTHAT = ""), {
    # With the off-switch lifted and mirai present, offloading WOULD engage...
    expect_true(genescout_llm_offload_available())
    withr::with_options(list(genescout.llm.offload = FALSE), {
      # ...but the opt-out forces the in-process path (available is FALSE, so
      # genescout_llm_run short-circuits before any daemon is started).
      expect_false(genescout_llm_offload_available())
      expect_equal(genescout_llm_run(function() 42), 42)
    })
  })
})

# Study-context priors wiring: a priors_id loads context/<id>.yaml into
# context$priors, which the caveats + context-matching stages read. Offline (stub
# resolver + registry). CANDID_APP_ROOT points the loader at the app root, since
# tests run from tests/testthat.

app_root <- function() normalizePath(test_path("..", ".."))

test_that("run_enrich() loads study-context priors from a priors_id", {
  enr <- withr::with_envvar(
    c(CANDID_APP_ROOT = app_root()),
    run_enrich(
      list(mine = c("NF1", "TP53")),
      registry = stub_registry(),
      resolver = stub_resolver,
      context = list(priors_id = "lynch")
    )
  )
  priors <- enr$context[["priors"]]
  expect_false(is.null(priors)) # the YAML was loaded
  expect_true("MLH1" %in% priors$known_drivers)
  expect_true(any(grepl("mismatch", priors$pathways, ignore.case = TRUE)))
  expect_true("TTN" %in% priors$flags_genes)
})

test_that("run_enrich() leaves priors NULL when no priors_id is given", {
  enr <- run_enrich(
    list(mine = c("NF1", "TP53")),
    registry = stub_registry(),
    resolver = stub_resolver
  )
  expect_null(enr$context[["priors"]]) # opt-in: a plain run is unchanged
})

test_that("a bad priors_id degrades to no priors rather than crashing", {
  enr <- withr::with_envvar(
    c(CANDID_APP_ROOT = app_root()),
    run_enrich(
      list(mine = c("NF1", "TP53")),
      registry = stub_registry(),
      resolver = stub_resolver,
      context = list(priors_id = "no-such-context")
    )
  )
  expect_null(enr$context[["priors"]])
})

test_that("run_review_request() threads priors_id into the run's priors", {
  # The serializable envelope carries priors_id; a review through it loads the
  # same priors (the cross-language surface used by the CLI / API).
  res <- withr::with_envvar(
    c(CANDID_APP_ROOT = app_root()),
    run_review_request(
      list(
        sources = candidate_set(candid_source(
          c("NF1", "TP53"),
          label = "mine"
        )),
        priors_id = "lynch",
        options = list(caveats = TRUE)
      ),
      registry = stub_registry(),
      resolver = stub_resolver
    )
  )
  # The loaded flags extend the veto set; a run carries its context priors through.
  expect_true("TTN" %in% res$context[["priors"]]$flags_genes)
})

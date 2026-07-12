# Disease-context loader - listing + loading the priors YAMLs (offline).

# Tests run with the CWD at tests/testthat, so point at the app-root context dir.
ctx_dir <- function() test_path("..", "..", "context")

test_that("list_contexts() returns the shipped context ids", {
  ids <- list_contexts(ctx_dir())
  expect_true("nf1" %in% ids)
  # It is a named id -> id vector, so a UI picker can use it directly.
  expect_equal(unname(ids[["nf1"]]), "nf1")
})

test_that("load_context() loads a context's priors as a list", {
  ctx <- load_context("nf1", ctx_dir())
  expect_true(is.list(ctx))
  # The NF1 reference context carries the priors the engine reads.
  expect_false(is.null(ctx$pathways))
  expect_false(is.null(ctx$flags_genes))
})

test_that("load_context() errors on an unknown id", {
  expect_error(load_context("no-such-context", ctx_dir()), "Context not found")
})

# Parallel enrichment dispatch + gating (offline). The parallel path itself (mirai
# daemons + live HTTP) is verified by dev/smoke_parallel.R, NOT here: these tests lock
# in that the suite stays serial and deterministic (never spawns a worker) and that the
# dispatcher's output is byte-identical to the serial enrich_genes().

test_that("the parallel path is disabled under testthat (suite stays serial)", {
  # testthat sets TESTTHAT=true, which genescout_parallel_available() treats as a hard
  # off-switch - so CI never spawns worker processes regardless of list size.
  expect_false(genescout_parallel_available())
  expect_equal(genescout_parallel_workers(500), 1L)
  # Even a list well past the parallel threshold resolves to 1 worker here.
  expect_equal(
    genescout_parallel_workers(GENESCOUT_PARALLEL_MIN_GENES + 50),
    1L
  )
})

test_that("enrich_genes_dispatch() output is identical to serial enrich_genes()", {
  resolved <- resolve_genes(
    flatten_gene_lists(list(mine = c("NF1", "TP53"))),
    resolver = stub_resolver
  )
  reg <- stub_registry()
  serial <- enrich_genes(resolved, reg)
  disp <- enrich_genes_dispatch(resolved, reg)
  expect_equal(disp$signals_long, serial$signals_long)
  expect_equal(disp$evidence_long, serial$evidence_long)
})

test_that("enrich_genes_dispatch() forwards the progress callback per gene", {
  resolved <- resolve_genes(
    flatten_gene_lists(list(mine = c("NF1", "TP53"))),
    resolver = stub_resolver
  )
  seen <- integer(0)
  enrich_genes_dispatch(
    resolved,
    stub_registry(),
    progress = function(i, n, s) {
      seen[[length(seen) + 1L]] <<- i
    }
  )
  expect_equal(seen, 1:2)
})

test_that("worker count caps at the max and never exceeds the gene count", {
  # Lift the testthat off-switch (mirai is installed) to exercise the real arithmetic.
  # This computes a count only - genescout_parallel_workers() never spawns a daemon.
  withr::with_envvar(c(TESTTHAT = ""), {
    expect_true(genescout_parallel_available())
    expect_equal(
      genescout_parallel_workers(100),
      GENESCOUT_PARALLEL_MAX_WORKERS
    )
    expect_equal(genescout_parallel_workers(3), 3L)
    withr::with_options(list(genescout.parallel.workers = 2), {
      expect_equal(genescout_parallel_workers(100), 2L)
    })
    # The opt-out option forces the serial path even when mirai is present.
    withr::with_options(list(genescout.parallel = FALSE), {
      expect_false(genescout_parallel_available())
      expect_equal(genescout_parallel_workers(100), 1L)
    })
  })
})

test_that("genescout_engine_root() honors GENESCOUT_APP_ROOT, else the working dir", {
  withr::with_envvar(c(GENESCOUT_APP_ROOT = ""), {
    expect_equal(
      genescout_engine_root(),
      normalizePath(getwd(), winslash = "/", mustWork = FALSE)
    )
  })
  app_root <- test_path("..", "..")
  withr::with_envvar(c(GENESCOUT_APP_ROOT = app_root), {
    root <- genescout_engine_root()
    # A worker sources the engine from here, so enrich.R must resolve under it.
    expect_true(file.exists(file.path(root, "R", "enrich.R")))
  })
})

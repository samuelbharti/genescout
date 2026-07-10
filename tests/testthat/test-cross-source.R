# Cross-source corroboration: the input-derived breadth signal. Offline.
# The Balanced calibration (breadth beats a loud source, capped below High) is
# asserted in test-scoring.R; here we cover the count/gate mechanics and how
# run_enrich wires the signal in only for multi-source runs.

test_that("enrich_input_signals() counts distinct user sources, gates at >= 2", {
  resolved <- tibble::tibble(
    gene_id = c("G1", "G2", "G3"),
    symbol = c("AAA", "BBB", "CCC"),
    input_lists = list(c("degs", "atac"), c("degs"), c("degs", "atac", "wes"))
  )
  reg <- list(cross_source_signal())
  ctx <- list(user_sources = c("degs", "atac", "wes"))
  out <- enrich_input_signals(resolved, reg, ctx)
  s <- out$signals_long

  expect_equal(s$raw[s$gene_id == "G1"], 2)
  expect_equal(s$raw[s$gene_id == "G2"], 1)
  expect_equal(s$raw[s$gene_id == "G3"], 3)
  expect_true(s$present[s$gene_id == "G1"])
  expect_false(s$present[s$gene_id == "G2"]) # one source -> not corroborated
  expect_equal(s$normalized[s$gene_id == "G2"], 0) # neutral, never sub-baseline

  # Grounded provenance: one row per corroborating source, only when present.
  ev <- out$evidence_long
  expect_equal(nrow(ev[ev$gene_id == "G1", ]), 2)
  expect_equal(nrow(ev[ev$gene_id == "G2", ]), 0)
  expect_equal(nrow(ev[ev$gene_id == "G3", ]), 3)
  expect_true(all(nzchar(ev$source_id))) # survives the citation gate
  expect_true(all(ev$domain == "input-provenance"))
})

test_that("a disease-seed source is excluded from the corroboration count", {
  # resolved carries the injected 'disease: NF1' seed label, but user_sources
  # (captured from the non-seeded sources) excludes it, so it is not counted.
  resolved <- tibble::tibble(
    gene_id = "G1",
    symbol = "AAA",
    input_lists = list(c("degs", "disease: NF1"))
  )
  out <- enrich_input_signals(
    resolved,
    list(cross_source_signal()),
    list(user_sources = "degs")
  )
  expect_equal(out$signals_long$raw, 1)
  expect_false(out$signals_long$present)
})

test_that("run_enrich() appends cross_source only for >= 2 user sources", {
  one <- run_enrich(
    list(mine = c("NF1", "TP53")),
    registry = stub_registry(),
    resolver = stub_resolver
  )
  expect_false("cross_source" %in% one$registry$key)
  expect_false("cross_source_n" %in% names(one$genes))

  two <- run_enrich(
    list(mine = c("NF1"), other = c("NF1", "TP53")),
    registry = stub_registry(),
    resolver = stub_resolver
  )
  expect_true("cross_source" %in% two$registry$key)
  expect_true("cross_source_n" %in% names(two$genes))
  # NF1 is in both user sources -> corroborated (norm 0.5); TP53 in one -> 0.
  nf1 <- two$genes[two$genes$symbol == "NF1", ]
  tp53 <- two$genes[two$genes$symbol == "TP53", ]
  expect_equal(nf1$cross_source[[1]], 2)
  expect_equal(nf1$cross_source_n[[1]], 0.5)
  expect_equal(tp53$cross_source[[1]], 1)
  expect_equal(tp53$cross_source_n[[1]], 0)
})

test_that("the disease seed is not counted as user corroboration end-to-end", {
  # A discovery run with a single user source + a disease seed: the user gave
  # only one real source, so cross_source must NOT be appended.
  enr <- run_enrich(
    list(mine = c("NF1")),
    registry = stub_registry(),
    resolver = stub_resolver,
    context = list(disease = list(id = "MONDO:1", name = "NF1")),
    seeder = function(disease) {
      list(
        symbols = c("TP53", "SUZ12"),
        data = list(),
        n_seeded = 2
      )
    }
  )
  expect_false("cross_source" %in% enr$registry$key)
})

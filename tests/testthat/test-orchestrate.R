# run_review spine - deterministic merge -> rank, offline via helper stubs.

test_that("run_review() resolves, dedupes, enriches, and ranks", {
  out <- run_review(
    list(mine = c("NF1", "p53"), other = c("TP53")),
    description = "studying peripheral nerve tumors",
    registry = stub_registry(),
    resolver = stub_resolver
  )
  expect_equal(out$description, "studying peripheral nerve tumors")
  expect_false(out$generated_with_llm)
  # p53 + TP53 dedupe to one gene, plus NF1 -> 2 unique genes
  expect_equal(nrow(out$genes), 2)
  expect_true(all(
    c("rank", "symbol", "composite", "grade", "a", "a_n", "b", "b_n") %in%
      names(out$genes)
  ))
  expect_setequal(out$genes$rank, c(1, 2))
})

test_that("run_review() accepts a bare character vector or a data frame", {
  from_vec <- run_review(
    c("NF1"),
    registry = stub_registry(),
    resolver = stub_resolver
  )
  expect_equal(nrow(from_vec$genes), 1)

  df <- data.frame(gene = c("NF1", "TP53"), stringsAsFactors = FALSE)
  from_df <- run_review(
    df,
    registry = stub_registry(),
    resolver = stub_resolver
  )
  expect_equal(nrow(from_df$genes), 2)
})

test_that("run_review() errors on an empty gene list", {
  expect_error(
    run_review(list(), registry = stub_registry(), resolver = stub_resolver),
    "No genes"
  )
})

test_that("run_review() carries grounded evidence through the citation gate", {
  out <- run_review(
    list(mine = "NF1"),
    registry = stub_registry(),
    resolver = stub_resolver
  )
  expect_true(nrow(out$evidence) >= 1)
  expect_true(all(nzchar(out$evidence$source_id)))
})

test_that("run_enrich() + rank_result() split re-ranks without re-enriching", {
  enr <- run_enrich(
    list(mine = c("NF1", "TP53")),
    registry = stub_registry(),
    resolver = stub_resolver
  )
  # Enrichment is unranked and keeps the registry object for cheap re-ranking.
  expect_false("composite" %in% names(enr$genes))
  expect_true("registry_obj" %in% names(enr))

  ranked <- rank_result(enr)
  expect_setequal(ranked$genes$rank, c(1, 2))
  expect_equal(ranked$genes$symbol[1], "NF1") # composite 0.75 > 0.25
  expect_false("registry_obj" %in% names(ranked))
  expect_false(ranked$generated_with_llm)

  # A weight override on the SAME enriched object re-ranks with no re-enrich.
  flipped <- rank_result(enr, weights = c(a = 0, b = 1))
  expect_false(identical(flipped$genes$composite, ranked$genes$composite))
})

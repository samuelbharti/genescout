# run_review spine - deterministic merge -> rank, offline via helper stubs.

# Single source here so the spine test stays isolated from the cross-source
# signal (which only appends with >= 2 user sources); multi-source behavior is
# covered in test-cross-source.R.
test_that("run_review() resolves, dedupes, enriches, and ranks", {
  out <- run_review(
    list(mine = c("NF1", "p53", "TP53")),
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

test_that("run_review_request() unpacks an envelope (candidate_set + JSON form)", {
  req <- list(
    sources = candidate_set(genescout_source(c("NF1", "TP53"), label = "mine")),
    description = "peripheral nerve tumors",
    options = list(caveats = FALSE)
  )
  out <- run_review_request(
    req,
    registry = stub_registry(),
    resolver = stub_resolver
  )
  expect_equal(nrow(out$genes), 2)
  expect_setequal(out$genes$rank, c(1, 2))

  # The plain list-of-source-objects a non-R frontend posts (must NOT be read as
  # a bare named list - each element is a source object, not a gene vector).
  json_sources <- candidate_set_to_list(
    candidate_set(genescout_source(c("NF1"), label = "mine"))
  )
  out2 <- run_review_request(
    list(sources = json_sources),
    registry = stub_registry(),
    resolver = stub_resolver
  )
  expect_equal(nrow(out2$genes), 1)
  expect_equal(out2$genes$symbol, "NF1")
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

test_that("run_enrich() caps the candidate list at max_genes and audits it", {
  enr <- run_enrich(
    list(mine = c("NF1", "TP53", "AAA", "BBB", "CCC")),
    registry = stub_registry(),
    resolver = stub_resolver,
    max_genes = 2
  )
  expect_lte(nrow(enr$genes), 2) # only the kept tokens are resolved/enriched
  cap <- enr$context[["input_capped"]]
  expect_equal(cap$kept, 2)
  expect_equal(cap$total, 5)
  # The truncation is surfaced in the run provenance for the audit trail.
  prov <- vapply(enr$provenance, function(s) s$source %||% "", character(1))
  expect_true(any(grepl("Input cap", prov)))
})

test_that("run_enrich() default (max_genes = Inf) never caps", {
  enr <- run_enrich(
    list(mine = c("NF1", "TP53")),
    registry = stub_registry(),
    resolver = stub_resolver
  )
  expect_null(enr$context[["input_capped"]])
})

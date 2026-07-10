# GTEx tissue-expression client - offline parsers, tissue matching, relevance,
# and the unrelated-tissue caveat. No network.

test_that("gtex_gencode_parse() pulls the first record's gencode id", {
  gid <- gtex_gencode_parse(read_fixture("gtex_reference_tp53.json"))
  expect_equal(gid, "ENSG00000141510.16")
})

test_that("gtex_gencode_parse() returns NA on an empty body", {
  expect_true(is.na(gtex_gencode_parse(list(data = list()))))
})

test_that("gtex_expression_parse() distills tissue -> median TPM", {
  ex <- gtex_expression_parse(read_fixture("gtex_median_tp53.json"))
  expect_setequal(ex$tissue, c("Nerve_Tibial", "Liver", "Brain_Cortex"))
  expect_equal(ex$median[ex$tissue == "Nerve_Tibial"], 30.5)
})

test_that("gtex_tokens() drops short/generic words so matches stay specific", {
  expect_true("nerve" %in% gtex_tokens("peripheral nerve"))
  expect_true("schwann" %in% gtex_tokens("Schwann cell"))
  expect_false("cell" %in% gtex_tokens("Schwann cell")) # generic -> dropped
})

test_that("gtex_relevant() maps a tissue of interest to a GTEx tissue", {
  ex <- gtex_expression_parse(read_fixture("gtex_median_tp53.json"))
  expect_equal(gtex_relevant(ex, "peripheral nerve")$tissue, "Nerve_Tibial")
  # 'Schwann cell' maps to no GTEx tissue in this set.
  expect_equal(nrow(gtex_relevant(ex, "Schwann cell")), 0)
})

test_that("gtex_relevance() rewards tissue-of-interest expression", {
  ex <- gtex_expression_parse(read_fixture("gtex_median_tp53.json"))
  rel <- gtex_relevance(ex, "peripheral nerve")
  expect_true(rel$present)
  # nerve (30.5) / peak across all tissues (brain, 40.0)
  expect_equal(round(rel$relevance, 3), round(30.5 / 40.0, 3))
})

test_that("gtex_relevance() flags an unrelated-tissue-only gene as low", {
  ex <- tibble::tibble(tissue = c("Nerve_Tibial", "Liver"), median = c(0.2, 50))
  rel <- gtex_relevance(ex, "peripheral nerve")
  expect_true(rel$present) # measured + expressed (in liver)
  expect_lt(rel$relevance, 0.1) # but essentially not in nerve
})

test_that("gtex_relevance() is a miss with no context or no expression", {
  ex <- gtex_expression_parse(read_fixture("gtex_median_tp53.json"))
  expect_false(gtex_relevance(ex, character())$present)
  none <- tibble::tibble(tissue = "Liver", median = 0.1) # below min_expressed
  expect_false(gtex_relevance(none, "liver")$present)
})

test_that("gtex_tissue_expression() rejects a blank gene", {
  expect_false(gtex_tissue_expression("")$ok)
})

test_that("apply_caveats() down-weights an unrelated-tissue-only gene", {
  genes <- tibble::tibble(
    symbol = c("AAA", "BBB"),
    composite = c(0.5, 0.5),
    gtex_tissue_present = c(TRUE, TRUE),
    gtex_tissue_n = c(0.8, 0.02), # AAA in-tissue; BBB expressed only elsewhere
    n_evidence_present = c(0L, 0L)
  )
  out <- apply_caveats(genes, list(gtex_tissue_signal()), enabled = TRUE)
  expect_equal(out$composite[out$symbol == "AAA"], 0.5) # untouched
  expect_lt(out$composite[out$symbol == "BBB"], 0.5) # down-weighted
  expect_true(any(grepl(
    "tissue",
    unlist(out$caveats[out$symbol == "BBB"])
  )))
})

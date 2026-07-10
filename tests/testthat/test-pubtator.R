# PubTator3 entity-tagged literature count - offline parser + entity-token logic.
# No network.

test_that("pubtator_search_count_parse() reads the top-level article count", {
  n <- pubtator_search_count_parse(read_fixture("pubtator_search_tp53.json"))
  expect_equal(n, 287754L)
})

test_that("pubtator_search_count_parse() reads a real zero and a missing count", {
  expect_equal(
    pubtator_search_count_parse(read_fixture("pubtator_search_zero.json")),
    0L
  )
  expect_true(is.na(pubtator_search_count_parse(list(results = list()))))
})

test_that("pubtator_entity_token() prefers the NCBI Gene id, falls back to symbol", {
  expect_equal(pubtator_entity_token("TP53", entrez = "7157"), "@GENE_7157")
  expect_equal(pubtator_entity_token("tp53", entrez = NA), "@GENE_TP53")
  expect_equal(pubtator_entity_token("Nf1", entrez = ""), "@GENE_NF1")
  # A non-numeric entrez is ignored (falls back to the symbol).
  expect_equal(pubtator_entity_token("TP53", entrez = "abc"), "@GENE_TP53")
})

test_that("pubtator_entity_token() is NA for a blank or unusable gene", {
  expect_true(is.na(pubtator_entity_token("", entrez = NULL)))
  expect_true(is.na(pubtator_entity_token(NA, entrez = NULL)))
  expect_true(is.na(pubtator_entity_token("bad symbol!", entrez = NULL)))
})

test_that("pubtator_gene_literature() rejects a blank gene without a network call", {
  expect_false(pubtator_gene_literature("")$ok)
  expect_false(pubtator_gene_literature(NA)$ok)
})

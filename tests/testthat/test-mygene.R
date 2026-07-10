# MyGene client - offline parser + query-builder tests.

test_that("mygene_parse_hit() normalizes a MyGene hit", {
  hit <- read_fixture("mygene_tp53.json")$hits[[1]]
  res <- mygene_parse_hit(hit, fallback_symbol = "TP53")

  expect_true(res$ok)
  expect_equal(res$symbol, "TP53")
  expect_equal(res$entrez, "7157")
  expect_equal(res$ensembl_gene, "ENSG00000141510")
  expect_equal(res$uniprot, "P04637")
  expect_match(res$summary, "tumor suppressor")
})

test_that("mygene query helpers detect id types and clean input", {
  expect_equal(
    mygene_query_term("ENSG00000141510"),
    "ensembl.gene:ENSG00000141510"
  )
  expect_equal(mygene_query_term("7157"), "entrezgene:7157")
  expect_equal(mygene_query_term("TP53"), "TP53")
  expect_equal(mygene_clean_symbol("  TP53; "), "TP53")
  expect_null(mygene_clean_symbol("   "))
})

test_that("mygene_first() takes the first of scalar-or-list fields", {
  expect_equal(mygene_first(list("P04637", "X")), "P04637")
  expect_equal(mygene_first("P04637"), "P04637")
  expect_true(is.na(mygene_first(NULL)))
})

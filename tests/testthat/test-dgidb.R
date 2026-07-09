# DGIdb drug-gene interaction client - offline parser tests.

test_that("dgidb_interactions_parse() counts interactions", {
  r <- dgidb_interactions_parse(read_fixture("dgidb_nf1.json"), "NF1")
  expect_true(r$ok)
  expect_equal(r$count, 2L)
  expect_match(r$source_id, "DGIdb:gene:NF1")
  expect_match(r$source_url, "hgnc:7765")
})

test_that("dgidb_interactions_parse() treats 0 interactions as a real zero", {
  r <- dgidb_interactions_parse(read_fixture("dgidb_zero.json"), "XYZ")
  expect_true(r$ok)
  expect_equal(r$count, 0L)
})

test_that("dgidb_interactions_parse() is a miss when the gene is absent", {
  r <- dgidb_interactions_parse(read_fixture("dgidb_empty.json"), "XYZ")
  expect_false(r$ok)
})

test_that("dgidb_gene_interactions() rejects a blank symbol", {
  expect_false(dgidb_gene_interactions("")$ok)
})

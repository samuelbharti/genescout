# CIViC clinical-evidence client - offline parser. No network.

test_that("civic_gene_parse() distills the gene's curated evidence-item count", {
  r <- civic_gene_parse(read_fixture("civic_nf1.json"))
  expect_true(r$ok)
  expect_equal(r$evidence_items, 56)
  expect_equal(r$variants, 37)
  expect_equal(r$source_id, "CIViC:gene:3867")
  expect_match(r$source_url, "civicdb.org")
})

test_that("civic_gene_parse() reports a miss when CIViC has no such gene", {
  expect_false(civic_gene_parse(list(data = list(gene = NULL)))$ok)
  expect_false(civic_gene_parse(list())$ok)
})

test_that("civic_gene_evidence() rejects a blank symbol and sanitizes the token", {
  expect_false(civic_gene_evidence("")$ok)
  # A symbol of only illegal characters sanitizes to empty -> rejected (no query).
  expect_false(civic_gene_evidence("{}\"")$ok)
})

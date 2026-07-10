# gnomAD gene-constraint (LOEUF) client - offline parser tests.

test_that("gnomad_constraint_parse() extracts LOEUF and pLI", {
  r <- gnomad_constraint_parse(read_fixture("gnomad_nf1.json"), "NF1")
  expect_true(r$ok)
  expect_equal(r$loeuf, 0.29)
  expect_equal(r$pli, 1.0)
  expect_match(r$source_id, "gnomAD:gene:NF1")
  expect_match(r$source_url, "/NF1")
})

test_that("gnomad_constraint_parse() is a miss when constraint is absent", {
  r <- gnomad_constraint_parse(read_fixture("gnomad_missing.json"), "XYZ")
  expect_false(r$ok)
})

test_that("gnomad_constraint_parse() is a miss when the gene is absent", {
  r <- gnomad_constraint_parse(list(data = list(gene = NULL)), "XYZ")
  expect_false(r$ok)
})

test_that("gnomad_loeuf() rejects a blank symbol", {
  expect_false(gnomad_loeuf("")$ok)
})

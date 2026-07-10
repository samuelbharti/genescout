# cBioPortal mutation-frequency client - offline parser. No network.

test_that("cbioportal_frequency_parse() computes the mutated fraction", {
  r <- cbioportal_frequency_parse(read_fixture("cbioportal_nf1.json"), "NF1")
  expect_true(r$ok)
  expect_equal(r$mutated, 591)
  expect_equal(r$total, 591 + 10354)
  expect_equal(round(r$frequency, 5), round(591 / 10945, 5))
  expect_equal(r$source_id, "cbioportal:msk_impact_2017")
  expect_match(r$source_url, "cbioportal.org")
})

test_that("cbioportal_frequency_parse() reports a miss for an empty payload", {
  expect_false(cbioportal_frequency_parse(list(), "NF1")$ok)
  expect_false(
    cbioportal_frequency_parse(
      list(list(hugoGeneSymbol = "NF1", counts = list())),
      "NF1"
    )$ok
  )
})

test_that("cbioportal_gene_frequency() rejects a blank symbol", {
  expect_false(cbioportal_gene_frequency("")$ok)
})

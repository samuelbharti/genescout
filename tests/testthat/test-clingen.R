# ClinGen gene-disease validity client - offline CSV parser + context relevance.
# No network (the bulk CSV is read from a recorded fixture).

test_that("clingen_read_csv() parses the banner CSV to tidy curations", {
  rows <- clingen_read_csv(read_fixture_text("clingen_gene_validity.csv"))
  expect_true(all(
    c("gene", "hgnc", "disease", "mondo", "classification", "report_url") %in%
      names(rows)
  ))
  expect_true("NF1" %in% rows$gene)
  nf1 <- rows[rows$gene == "NF1", ]
  expect_equal(nrow(nf1), 2)
  expect_true("Definitive" %in% nf1$classification)
  expect_equal(
    nf1$mondo[nf1$disease == "neurofibromatosis type 1"],
    "MONDO:0018975"
  )
})

test_that("clingen_read_csv() returns an empty frame for junk / no header", {
  expect_equal(nrow(clingen_read_csv("")), 0)
  expect_equal(nrow(clingen_read_csv("not,a,clingen,file")), 0)
})

test_that("clingen_strength() maps classifications to ordinal strength", {
  expect_equal(
    clingen_strength(c("Definitive", "Strong", "Moderate", "Limited")),
    c(4L, 3L, 2L, 1L)
  )
  expect_equal(clingen_strength("No Known Disease Relationship"), 0L)
  expect_equal(clingen_strength(NA), 0L)
})

test_that("clingen_relevance() scopes to the disease context by MONDO / name", {
  rows <- clingen_read_csv(read_fixture_text("clingen_gene_validity.csv"))
  nf1 <- rows[rows$gene == "NF1", ]
  # MONDO match with the PRODUCTION id shape: Open Targets underscore vs ClinGen
  # colon. Only the Definitive neurofibromatosis curation matches (the "No Known
  # Disease Relationship" familial-ovarian row is not established).
  rel <- clingen_relevance(
    nf1,
    list(id = "MONDO_0018975", name = "neurofibromatosis type 1")
  )
  expect_true(rel$present)
  expect_equal(rel$strength, 4L)
  expect_equal(rel$matched$disease, "neurofibromatosis type 1")
})

test_that("clingen_relevance() counts only established curations without a context", {
  rows <- clingen_read_csv(read_fixture_text("clingen_gene_validity.csv"))
  nf1 <- rows[rows$gene == "NF1", ]
  rel <- clingen_relevance(nf1, NULL)
  expect_true(rel$present)
  expect_equal(nrow(rel$matched), 1) # the "No Known Disease Relationship" row drops
  expect_equal(rel$strength, 4L)
})

test_that("clingen_relevance() is a miss when nothing matches the context", {
  rows <- clingen_read_csv(read_fixture_text("clingen_gene_validity.csv"))
  nf1 <- rows[rows$gene == "NF1", ]
  expect_false(clingen_relevance(nf1, list(name = "asthma"))$present)
})

test_that("clingen_gene_validity() rejects a blank symbol", {
  expect_false(clingen_gene_validity("")$ok)
})

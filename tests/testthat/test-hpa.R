# Human Protein Atlas client - offline parser + disease/cancer relevance. No network.

test_that("hpa_parse() pulls protein class + disease involvement", {
  p <- hpa_parse(read_fixture("hpa_tp53.json"))
  expect_equal(p$gene, "TP53")
  expect_true("Tumor suppressor" %in% p$disease_involvement)
  expect_true("Cancer-related genes" %in% p$protein_class)
})

test_that("hpa_relevance() counts distinct disease/cancer classifications", {
  hpa <- hpa_parse(read_fixture("hpa_tp53.json"))
  rel <- hpa_relevance(hpa)
  expect_true(rel$present)
  # TP53's disease/cancer tags: Cancer-related genes, Disease related genes,
  # Human disease related genes, Disease variant, Tumor suppressor (deduped = 5).
  expect_equal(rel$n, 5)
  expect_true("Tumor suppressor" %in% rel$tags)
  # A non-disease class (e.g. Transcription factors) is not counted.
  expect_false("Transcription factors" %in% rel$tags)
})

test_that("hpa_relevance() is absent for a gene with no disease classes", {
  hpa <- list(
    protein_class = c("Predicted intracellular proteins"),
    disease_involvement = character()
  )
  rel <- hpa_relevance(hpa)
  expect_false(rel$present)
  expect_equal(rel$n, 0)
})

test_that("hpa_gene() rejects a non-Ensembl id", {
  expect_false(hpa_gene("")$ok)
  expect_false(hpa_gene("TP53")$ok)
})

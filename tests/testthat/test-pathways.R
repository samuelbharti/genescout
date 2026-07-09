# Reactome pathway client - offline parser + relevance tests.

test_that("reactome_pathways_parse() distills pathways with stable ids", {
  r <- reactome_pathways_parse(read_fixture("reactome_nf1.json"), "NF1")
  expect_true(r$ok)
  expect_equal(nrow(r$pathways), 3)
  expect_true(any(r$pathways$in_disease)) # the NF1 LoF pathway
  expect_equal(r$pathways$source_id[1], "Reactome:R-HSA-5658442")
  expect_match(
    r$pathways$source_url[1],
    "reactome.org/content/detail/R-HSA-5658442"
  )
})

test_that("reactome_pathways_parse() is a miss on an empty array", {
  r <- reactome_pathways_parse(read_fixture("reactome_empty.json"), "XYZ")
  expect_false(r$ok)
})

test_that("reactome_relevant() keeps disease pathways, drops generic ones", {
  nf1 <- reactome_pathways_parse(
    read_fixture("reactome_nf1.json"),
    "NF1"
  )$pathways
  ttn <- reactome_pathways_parse(
    read_fixture("reactome_ttn.json"),
    "TTN"
  )$pathways

  # No context: only the disease-associated pathway is relevant for NF1.
  expect_equal(nrow(reactome_relevant(nf1)), 1)
  # TTN's pathways are generic (muscle) and not disease-flagged -> nothing.
  expect_equal(nrow(reactome_relevant(ttn)), 0)
  # A RAS/MAPK context also pulls in the RAS-NAMED pathways (both "RAS ..."
  # pathways), but not the RAC1 one - so the disease-only set of 1 grows to 2.
  expect_equal(nrow(reactome_relevant(nf1, c("RAS/MAPK"))), 2)
})

test_that("pathway_matches_context() token-matches Reactome names to priors", {
  m <- pathway_matches_context(
    c("Regulation of RAS by GAPs", "Striated Muscle Contraction"),
    c("RAS/MAPK", "TP53")
  )
  expect_equal(m, c(TRUE, FALSE))
  # No context -> nothing matches.
  expect_equal(
    pathway_matches_context(c("Regulation of RAS by GAPs"), NULL),
    FALSE
  )
})

test_that("reactome_pathways() rejects a blank symbol", {
  expect_false(reactome_pathways("")$ok)
})

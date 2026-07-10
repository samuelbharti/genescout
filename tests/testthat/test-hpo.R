# HPO gene-disease client - offline parser + context relevance. No network.

test_that("hpo_diseases_parse() distills gene-associated diseases", {
  d <- hpo_diseases_parse(read_fixture("hpo_tp53.json"))
  expect_equal(nrow(d), 4)
  expect_true(all(c("id", "name", "mondo") %in% names(d)))
  expect_true("Li-Fraumeni syndrome" %in% d$name)
  expect_equal(d$mondo[d$name == "Li-Fraumeni syndrome"], "MONDO:0018875")
})

test_that("hpo_diseases_parse() returns an empty frame for no diseases", {
  expect_equal(nrow(hpo_diseases_parse(list(diseases = list()))), 0)
  expect_equal(nrow(hpo_diseases_parse(list())), 0)
})

test_that("hpo_relevance() counts all diseases with no disease context", {
  d <- hpo_diseases_parse(read_fixture("hpo_tp53.json"))
  rel <- hpo_relevance(d, disease_ctx = NULL)
  expect_true(rel$present)
  expect_equal(rel$n, 4)
})

test_that("hpo_relevance() scopes to the disease context by name/MONDO", {
  d <- hpo_diseases_parse(read_fixture("hpo_tp53.json"))
  # Name-token match: "Li-Fraumeni" context matches the Li-Fraumeni disease.
  rel <- hpo_relevance(d, disease_ctx = list(name = "Li-Fraumeni syndrome"))
  expect_true(rel$present)
  expect_equal(rel$n, 1)
  expect_equal(rel$matched$name, "Li-Fraumeni syndrome")
  # MONDO match works too.
  rel2 <- hpo_relevance(d, disease_ctx = list(id = "MONDO:0007256"))
  expect_true(rel2$present)
  expect_equal(rel2$matched$name, "Hepatocellular carcinoma")
  # An unrelated context matches nothing -> not present.
  rel3 <- hpo_relevance(d, disease_ctx = list(name = "neurofibromatosis"))
  expect_false(rel3$present)
})

test_that("hpo_gene_diseases() rejects a gene with no NCBI Gene id", {
  expect_false(hpo_gene_diseases("")$ok)
  expect_false(hpo_gene_diseases("notanid")$ok)
})

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
  # MONDO match works too - and with the PRODUCTION id shape (Open Targets uses the
  # underscore form MONDO_0007256; HPO's mondoId is the colon form MONDO:0007256).
  # The separator must be normalized or this id-match is dead in every real run.
  rel2 <- hpo_relevance(d, disease_ctx = list(id = "MONDO_0007256"))
  expect_true(rel2$present)
  expect_equal(rel2$matched$name, "Hepatocellular carcinoma")
  # An unrelated context matches nothing -> not present.
  rel3 <- hpo_relevance(d, disease_ctx = list(name = "neurofibromatosis"))
  expect_false(rel3$present)
})

test_that("hpo_relevance() matches an underscore context id against HPO's colon id", {
  # Only the MONDO ids agree (names are deliberately unrelated), so this passes only
  # if the separator is normalized (MONDO_0018875 <-> MONDO:0018875).
  d <- tibble::tibble(
    id = c("OMIM:1", "OMIM:2"),
    name = c("Some unrelated label", "Another label"),
    mondo = c("MONDO:0018875", "MONDO:0000001")
  )
  rel <- hpo_relevance(
    d,
    disease_ctx = list(id = "MONDO_0018875", name = "Li-Fraumeni syndrome")
  )
  expect_true(rel$present)
  expect_equal(rel$n, 1)
  expect_equal(rel$matched$mondo, "MONDO:0018875")
})

test_that("hpo_diseases_parse() yields id = NA for a disease with no id key", {
  parsed <- hpo_diseases_parse(list(
    diseases = list(
      list(mondoId = "MONDO:0011111", name = "Some disease") # no 'id'
    )
  ))
  expect_equal(nrow(parsed), 1)
  expect_true(is.na(parsed$id))
})

test_that("HPO per-disease source_id falls back to the gene-level id for a null id", {
  # Regression: nzchar(NA) is TRUE and ifelse() with an NA condition returns NA, so
  # without the is.na() guard a null-id disease row would carry source_id = NA and be
  # dropped by the citation gate (still counted in raw) - an ungrounded mismatch.
  ev_id <- c("OMIM:1", NA_character_, "")
  gene_level <- "HPO:NCBIGene:7157"
  got <- ifelse(!is.na(ev_id) & nzchar(ev_id), ev_id, gene_level)
  expect_equal(got, c("OMIM:1", gene_level, gene_level))
  expect_false(any(is.na(got))) # every evidence row stays grounded
})

test_that("hpo_gene_diseases() rejects a gene with no NCBI Gene id", {
  expect_false(hpo_gene_diseases("")$ok)
  expect_false(hpo_gene_diseases("notanid")$ok)
})

# IMPC mouse-knockout client - offline parsers: human->mouse resolution + distinct
# significant phenotypes. No network.

test_that("impc_ortholog_parse() maps a human symbol to its mouse MGI accession", {
  r <- impc_ortholog_parse(read_fixture("impc_gene_nf1.json"))
  expect_true(r$ok)
  expect_equal(r$mgi, "MGI:97306")
  expect_equal(r$marker_symbol, "Nf1")
})

test_that("impc_ortholog_parse() misses when there is no mouse ortholog / MGI id", {
  expect_false(impc_ortholog_parse(list(response = list(docs = list())))$ok)
  expect_false(impc_ortholog_parse(list())$ok)
  # A doc without a valid MGI accession is a miss (never a fabricated key).
  bad <- list(response = list(docs = list(list(marker_symbol = "Nf1"))))
  expect_false(impc_ortholog_parse(bad)$ok)
})

test_that("impc_phenotypes_parse() collapses to distinct grounded phenotype terms", {
  ph <- impc_phenotypes_parse(read_fixture("impc_pheno_nf1.json"), "MGI:97306")
  # IMPC repeats a phenotype across sex/zygosity/parameter rows; we keep distinct
  # ontology terms (NF1: preweaning lethality + inflammation).
  expect_equal(nrow(ph), 2)
  expect_false(any(duplicated(ph$mp_id)))
  expect_true("MP:0011100" %in% ph$mp_id)
  # Each term is grounded by the knockout allele + the term id, and links to the
  # IMPC gene page.
  row <- ph[ph$mp_id == "MP:0011100", ]
  expect_match(row$source_id, "^IMPC:MGI:", perl = TRUE)
  expect_match(row$source_id, "MP:0011100$", perl = TRUE)
  expect_match(
    row$source_url,
    "mousephenotype.org/data/genes/MGI:97306",
    fixed = TRUE
  )
})

test_that("impc_phenotypes_parse() returns an empty frame for no phenotypes", {
  expect_equal(
    nrow(impc_phenotypes_parse(list(response = list(docs = list())))),
    0
  )
  expect_equal(nrow(impc_phenotypes_parse(list())), 0)
})

test_that("impc_mouse_ortholog() rejects a blank symbol", {
  expect_false(impc_mouse_ortholog("")$ok)
})

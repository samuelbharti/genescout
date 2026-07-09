# Gene-level ClinVar pathogenic-count client - offline parser tests.

test_that("clinvar_gene_count_parse() reads the esearch hit count", {
  expect_equal(
    clinvar_gene_count_parse(read_fixture("clinvar_gene_nf1.json")),
    1287L
  )
})

test_that("clinvar_gene_count_parse() treats 0 as a real zero, not NA", {
  expect_equal(
    clinvar_gene_count_parse(read_fixture("clinvar_gene_zero.json")),
    0L
  )
})

test_that("clinvar_gene_count_parse() returns NA when count is absent", {
  expect_true(is.na(clinvar_gene_count_parse(list(esearchresult = list()))))
  expect_true(is.na(clinvar_gene_count_parse(list())))
})

test_that("clinvar_gene_pathogenic_term() builds a gene + clinsig query", {
  term <- clinvar_gene_pathogenic_term("NF1")
  expect_match(term, "NF1\\[gene\\]")
  expect_match(term, "pathogenic", ignore.case = TRUE)
  expect_match(term, "likely pathogenic", ignore.case = TRUE)
})

test_that("clinvar_gene_pathogenic_count() rejects a blank symbol", {
  expect_false(clinvar_gene_pathogenic_count("")$ok)
})

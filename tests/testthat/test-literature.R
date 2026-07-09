# Literature client (Europe PMC) - offline parser + query-builder tests.

test_that("europepmc_parse_results() builds a grounded citation tibble", {
  results <- read_fixture("europepmc_nf1.json")$resultList$result
  d <- europepmc_parse_results(results)

  expect_s3_class(d, "data.frame")
  expect_true(all(
    c(
      "title",
      "authors",
      "year",
      "journal",
      "pmid",
      "source",
      "source_id",
      "source_url"
    ) %in%
      names(d)
  ))
  expect_equal(nrow(d), length(results))
  expect_true(all(nzchar(d$source_id)))
  expect_true(all(grepl("^(PMID:|[A-Z]+:)", d$source_id)))
  expect_true(all(startsWith(d$source_url, "https://europepmc.org/article/")))
})

test_that("literature_query() ANDs the gene with context terms", {
  ctx <- list(search_terms = c("MPNST", "neurofibromatosis type 1"))
  q <- literature_query("NF1", ctx)
  expect_match(q, '^"NF1" AND \\(')
  expect_match(q, "MPNST")
  expect_match(q, "neurofibromatosis type 1")
})

test_that("literature_query() falls back to the gene alone when no terms", {
  expect_equal(literature_query("NF1", list()), '"NF1"')
})

test_that("europepmc_count_parse() reads hitCount and keeps 0 as 0", {
  expect_equal(europepmc_count_parse(read_fixture("europepmc_nf1.json")), 2530L)
  expect_equal(europepmc_count_parse(read_fixture("europepmc_zero.json")), 0L)
  expect_true(is.na(europepmc_count_parse(list())))
})

test_that("europepmc_count() rejects a blank query", {
  expect_false(europepmc_count("")$ok)
})

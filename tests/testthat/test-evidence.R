# Evidence helpers - the pure Europe PMC query builder (offline, no network).

test_that("literature_query() falls back to the gene alone with no context terms", {
  expect_equal(literature_query("NF1", list()), '"NF1"')
  # Blank / NA terms are dropped, so an empty term set also falls back.
  expect_equal(
    literature_query("NF1", list(search_terms = c("", NA_character_))),
    '"NF1"'
  )
})

test_that("literature_query() ANDs the gene with quoted context terms", {
  q <- literature_query(
    "NF1",
    list(search_terms = c("neurofibromatosis type 1", "MPNST"))
  )
  expect_equal(q, '"NF1" AND ("neurofibromatosis type 1" OR "MPNST")')
})

test_that("literature_query() falls back label -> id when search_terms is absent", {
  expect_equal(
    literature_query("TP53", list(label = "Li-Fraumeni")),
    '"TP53" AND ("Li-Fraumeni")'
  )
  expect_equal(
    literature_query("TP53", list(id = "MONDO:0018875")),
    '"TP53" AND ("MONDO:0018875")'
  )
})

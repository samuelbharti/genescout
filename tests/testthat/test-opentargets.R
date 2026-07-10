# Open Targets client - offline parser tests against a recorded fixture. The
# fetch/parse split keeps these network-free (Phase 0 target, now implemented).

test_that("opentargets_parse_rows() builds a grounded evidence tibble", {
  target <- read_fixture("opentargets_tp53.json")$data$target
  rows <- target$associatedDiseases$rows
  ev <- opentargets_parse_rows(rows, "ENSG00000141510")

  expect_s3_class(ev, "data.frame")
  expect_true(all(
    c("disease", "disease_id", "score", "source_id", "source_url") %in%
      names(ev)
  ))
  expect_equal(nrow(ev), length(rows))
  expect_equal(ev$disease[1], "Li-Fraumeni syndrome")
  expect_true(is.numeric(ev$score))
})

test_that("every parsed row is grounded with a source id and Open Targets url", {
  target <- read_fixture("opentargets_tp53.json")$data$target
  ev <- opentargets_parse_rows(
    target$associatedDiseases$rows,
    "ENSG00000141510"
  )

  expect_true(all(nzchar(ev$source_id)))
  expect_true(all(startsWith(ev$source_id, "OpenTargets:ENSG00000141510:")))
  expect_true(all(startsWith(
    ev$source_url,
    "https://platform.opentargets.org/evidence/"
  )))
})

test_that("opentargets_parse_rows() returns an empty typed tibble for no rows", {
  ev <- opentargets_parse_rows(list(), "ENSG00000141510")
  expect_equal(nrow(ev), 0)
  expect_true("source_id" %in% names(ev))
})

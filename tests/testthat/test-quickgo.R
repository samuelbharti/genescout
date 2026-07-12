# QuickGO (Gene Ontology) client - offline parser + de-duplication. No network.

test_that("quickgo_annotations_parse() distills distinct GO biological processes", {
  r <- quickgo_annotations_parse(read_fixture("quickgo_nf1.json"), "P21359")
  expect_true(r$ok)
  # GO annotations repeat one term across evidence lines; the parser keeps one row
  # per GO id, so there are no duplicates.
  expect_false(any(duplicated(r$terms$go_id)))
  expect_true(all(grepl("^GO:", r$terms$go_id)))
  # A known NF1 biological-process term is present, with a readable name.
  expect_true("GO:0043409" %in% r$terms$go_id)
  row <- r$terms[r$terms$go_id == "GO:0043409", ]
  expect_true(nzchar(row$go_name))
  # Every term is grounded by its GO id and links to the QuickGO term page.
  expect_equal(row$source_id, "GO:0043409")
  expect_match(row$source_url, "QuickGO/term/GO:0043409", fixed = TRUE)
})

test_that("quickgo_annotations_parse() reports a miss when there are no results", {
  expect_false(quickgo_annotations_parse(list(results = list()), "X")$ok)
  expect_false(quickgo_annotations_parse(list(), "X")$ok)
})

test_that("quickgo_annotations() rejects a blank / non-accession id", {
  expect_false(quickgo_annotations("")$ok)
  # A token of only illegal characters sanitizes to empty -> rejected (no query).
  expect_false(quickgo_annotations("!!!")$ok)
})

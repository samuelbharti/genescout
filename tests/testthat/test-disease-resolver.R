# Open Targets disease resolver - offline parser tests. The fetch/parse split
# keeps these network-free; parsers run against recorded fixtures.

test_that("resolve_disease_parse() surfaces search hits, best match first", {
  matches <- resolve_disease_parse(read_fixture("ot_disease_search_nf1.json"))

  expect_s3_class(matches, "data.frame")
  expect_true(all(
    c("id", "name", "score", "description", "source_id", "source_url") %in%
      names(matches)
  ))
  expect_equal(nrow(matches), 4L)
  expect_equal(matches$id[1], "MONDO_0018975")
  expect_equal(matches$name[1], "neurofibromatosis type 1")
  expect_true(is.numeric(matches$score))
  # Best match first: Open Targets returns hits highest-score-first.
  expect_true(matches$score[1] >= matches$score[nrow(matches)])
})

test_that("every resolved disease is grounded with a source id and OT url", {
  matches <- resolve_disease_parse(read_fixture("ot_disease_search_nf1.json"))

  expect_true(all(nzchar(matches$source_id)))
  expect_true(all(startsWith(matches$source_id, "OpenTargets:disease:")))
  expect_equal(matches$source_id[1], "OpenTargets:disease:MONDO_0018975")
  expect_true(all(startsWith(
    matches$source_url,
    "https://platform.opentargets.org/disease/"
  )))
})

test_that("resolve_disease_parse() reads a single-disease lookup shape", {
  data <- list(
    data = list(
      disease = list(
        id = "MONDO_0018975",
        name = "neurofibromatosis type 1",
        description = "A tumor predisposition syndrome."
      )
    )
  )
  matches <- resolve_disease_parse(data)

  expect_equal(nrow(matches), 1L)
  expect_equal(matches$id[1], "MONDO_0018975")
  expect_equal(matches$name[1], "neurofibromatosis type 1")
  expect_true(is.na(matches$score[1]))
  expect_equal(matches$source_id[1], "OpenTargets:disease:MONDO_0018975")
})

test_that("resolve_disease_parse() returns an empty typed tibble for no data", {
  empty <- resolve_disease_parse(list(
    data = list(search = list(hits = list()))
  ))

  expect_equal(nrow(empty), 0L)
  expect_true(all(
    c("id", "name", "score", "description", "source_id", "source_url") %in%
      names(empty)
  ))
})

test_that("is_disease_id() distinguishes ontology ids from free text", {
  expect_true(is_disease_id("MONDO:0018975"))
  expect_true(is_disease_id("MONDO_0018975"))
  expect_true(is_disease_id("EFO_0000508"))
  expect_true(is_disease_id("Orphanet_636"))
  expect_false(is_disease_id("neurofibromatosis type 1"))
  expect_false(is_disease_id(""))
})

test_that("resolve_disease() rejects a blank term without a network call", {
  expect_false(resolve_disease("")$ok)
  expect_false(resolve_disease("   ")$ok)
  expect_false(resolve_disease(NULL)$ok)
})

test_that("ot_disease_doid_parse() picks the first DOID cross-reference", {
  data <- list(
    data = list(
      disease = list(
        id = "MONDO_0018975",
        dbXRefs = list("UMLS:C0027831", "DOID:0111253", "MESH:D009456")
      )
    )
  )
  expect_equal(ot_disease_doid_parse(data), "DOID:0111253")
})

test_that("ot_disease_doid_parse() returns NA when no DOID xref is present", {
  data <- list(data = list(disease = list(dbXRefs = list("UMLS:C0027831"))))
  expect_true(is.na(ot_disease_doid_parse(data)))
  expect_true(is.na(ot_disease_doid_parse(list(data = list(disease = list())))))
})

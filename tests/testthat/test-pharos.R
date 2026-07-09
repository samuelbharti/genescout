# Pharos TDL client - offline parser tests.

test_that("pharos_tdl_parse() maps TDL to a 0-1 score", {
  r <- pharos_tdl_parse(read_fixture("pharos_nf1.json"), "NF1")
  expect_true(r$ok)
  expect_equal(r$tdl, "Tbio")
  expect_equal(r$score, 0.5)
  expect_match(r$source_id, "Pharos:gene:NF1:Tbio")
})

test_that("pharos_tdl_parse() is a miss for an absent target", {
  expect_false(pharos_tdl_parse(list(data = list(target = NULL)), "XYZ")$ok)
})

test_that("pharos_tdl_parse() is a miss for an unknown TDL value", {
  bad <- list(data = list(target = list(sym = "XYZ", tdl = "Tnope")))
  expect_false(pharos_tdl_parse(bad, "XYZ")$ok)
})

test_that("pharos_tdl() rejects a blank symbol", {
  expect_false(pharos_tdl("")$ok)
})

test_that("guess_type() distinguishes genes from variants", {
  expect_equal(guess_type("NF1"), "gene")
  expect_equal(guess_type("rs1234"), "variant")
  expect_equal(guess_type("17-31350290-A-G"), "variant")
  expect_equal(guess_type("NM_000267.3:c.123A>G"), "variant")
})

test_that("parse_candidate_lines() drops blanks and comments", {
  out <- parse_candidate_lines("NF1\n\n# a comment\nSUZ12")
  expect_equal(nrow(out), 2)
  expect_equal(out$candidate, c("NF1", "SUZ12"))
  expect_true(all(out$type == "gene"))
})

test_that("parse_candidate_lines() errors on empty input", {
  expect_error(parse_candidate_lines("\n  \n"), "No candidates")
})

test_that("read_candidate_table() reads the bundled NF1 example", {
  path <- test_path("..", "..", "data", "examples", "nf1_candidates.tsv")
  out <- read_candidate_table(path)
  expect_true(all(c("candidate", "type", "gene") %in% names(out)))
  expect_true("NF1" %in% out$candidate)
  expect_true("TTN" %in% out$candidate)
})

test_that("parse_candidates() requires some input", {
  expect_error(
    parse_candidates(list(file = NULL, text = NULL)),
    "No candidates provided"
  )
})

test_that("example_text() returns the NF1 gene list as pasteable text", {
  dir <- test_path("..", "..", "data", "examples")
  txt <- example_text("nf1_candidates", dir = dir)
  genes <- strsplit(txt, "\n")[[1]]
  expect_length(genes, 6)
  expect_true(all(c("NF1", "SUZ12", "CDKN2A", "TTN") %in% genes))
})

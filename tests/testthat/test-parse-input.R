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

test_that("collect_gene_lists() names pasted lines and skips empty inputs", {
  lists <- collect_gene_lists("NF1\nTP53", NULL)
  expect_named(lists, "pasted")
  expect_equal(lists$pasted, c("NF1", "TP53"))
  expect_length(collect_gene_lists("", NULL), 0)
  expect_length(collect_gene_lists(NULL, NULL), 0)
})

test_that("collect_candidate_set() reads a headerless single-column upload", {
  # A bare one-per-line list (no gene/symbol/candidate header) is now valid input;
  # the first token that is not a known header word is kept as a gene.
  p <- tempfile(fileext = ".csv")
  on.exit(unlink(p), add = TRUE)
  writeLines(c("notgene", "BRCA1", "TP53"), p)
  cs <- collect_candidate_set(list(list(name = "uploaded", file = p)))
  expect_null(candidate_parse_errors(cs))
  expect_length(cs, 1)
  expect_setequal(cs[[1]]$genes, c("notgene", "BRCA1", "TP53"))
})

test_that("collect_candidate_set() records a truly unreadable upload, not silent-drops it", {
  bad <- tempfile(fileext = ".csv")
  on.exit(unlink(bad), add = TRUE)
  file.create(bad) # empty file - no gene tokens at all
  cs <- collect_candidate_set(list(list(name = "uploaded", file = bad)))
  errs <- candidate_parse_errors(cs)
  expect_length(errs, 1)
  expect_equal(errs[[1]]$source, "uploaded")
  expect_match(errs[[1]]$message, "gene", ignore.case = TRUE)
  expect_length(cs, 0) # the bad source contributed nothing (no phantom source)
})

test_that("collect_candidate_set() attaches no parse_errors when sources are clean", {
  cs <- collect_candidate_set(list(list(name = "pasted", text = "NF1\nTP53")))
  expect_null(candidate_parse_errors(cs))
  expect_length(cs, 1)
})

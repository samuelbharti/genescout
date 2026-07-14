# Uploads accept a headerless single-column gene list (.txt/.tsv/.csv), and a
# source combines pasted + uploaded genes.

test_that("read_gene_list_file reads a headerless single-column list", {
  p <- tempfile(fileext = ".txt")
  writeLines(c("NF1", "SUZ12", "CDKN2A"), p)
  expect_equal(read_gene_list_file(p), c("NF1", "SUZ12", "CDKN2A"))
})

test_that("read_gene_list_file drops a header row and keeps the first column", {
  p <- tempfile(fileext = ".csv")
  writeLines(c("gene,note", "NF1,driver", "SUZ12,driver"), p)
  expect_equal(read_gene_list_file(p), c("NF1", "SUZ12"))
})

test_that("read_gene_list_file skips comments/blanks and errors when empty", {
  p <- tempfile(fileext = ".txt")
  writeLines(c("# a comment", "", "NF1", "  SUZ12  "), p)
  expect_equal(read_gene_list_file(p), c("NF1", "SUZ12"))
  e <- tempfile(fileext = ".txt")
  writeLines("# only a comment", e)
  expect_error(read_gene_list_file(e), "No gene symbols")
})

test_that("read_candidate_file handles a structured table and a bare list", {
  p1 <- tempfile(fileext = ".tsv")
  writeLines(c("gene\tscore", "NF1\t1", "TP53\t2"), p1)
  expect_equal(read_candidate_file(p1), c("NF1", "TP53"))
  p2 <- tempfile(fileext = ".txt")
  writeLines(c("NF1", "TP53"), p2)
  expect_equal(read_candidate_file(p2), c("NF1", "TP53"))
})

test_that("read_gene_list_file keeps a first-line gene that looks like a header (IDS)", {
  # IDS (iduronate 2-sulfatase) is a real HGNC symbol; it must not be dropped as a
  # header word when it is the first line of a headerless upload.
  p <- tempfile(fileext = ".txt")
  writeLines(c("IDS", "NF1", "SUZ12"), p)
  expect_equal(read_gene_list_file(p), c("IDS", "NF1", "SUZ12"))
})

test_that("read_gene_list_file strips surrounding quotes from a quoted CSV", {
  p <- tempfile(fileext = ".csv")
  writeLines(c('"NF1"', '"SUZ12"'), p)
  expect_equal(read_candidate_file(p), c("NF1", "SUZ12"))
})

test_that("read_candidate_file errors on a header-only upload (no data rows)", {
  p <- tempfile(fileext = ".csv")
  writeLines("gene", p)
  expect_error(read_candidate_file(p), "No gene symbols")
})

test_that("collect_candidate_set combines pasted text and an uploaded file", {
  p <- tempfile(fileext = ".txt")
  writeLines(c("EED", "TWIST1"), p)
  cs <- collect_candidate_set(list(
    list(name = "wes", type = "wes", text = "NF1\nSUZ12", file = p)
  ))
  expect_length(cs, 1)
  expect_setequal(cs[[1]]$genes, c("NF1", "SUZ12", "EED", "TWIST1"))
})

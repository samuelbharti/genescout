# The multi-source candidate model (genescout_source / candidate_set) and its
# coercions. Pure, offline: shapes and round-trips only, no network.

test_that("genescout_source() builds a classed record with sensible defaults", {
  s <- genescout_source(
    c("NF1", "TP53"),
    label = "my DEGs",
    type = "rnaseq_deg"
  )
  expect_s3_class(s, "genescout_source")
  expect_equal(s$label, "my DEGs")
  expect_equal(s$id, "my-degs") # slugified
  expect_equal(s$type, "rnaseq_deg")
  expect_false(s$seeded)
  expect_equal(s$genes, c("NF1", "TP53"))
})

test_that("as_candidate_set() maps a named list to one source per name", {
  cs <- as_candidate_set(list(mine = c("NF1"), other = c("TP53", "NF1")))
  expect_s3_class(cs, "genescout_candidate_set")
  expect_equal(length(cs), 2)
  expect_equal(
    vapply(cs, function(s) s$label, character(1)),
    c("mine", "other")
  )
  # id == label for the named-list shape, so input_lists stays byte-identical.
  expect_equal(vapply(cs, function(s) s$id, character(1)), c("mine", "other"))
})

test_that("as_candidate_set() handles bare vectors, data frames, and passthrough", {
  expect_equal(length(as_candidate_set(c("NF1", "TP53"))), 1)
  expect_equal(as_candidate_set(c("NF1"))[[1]]$label, "input")

  df <- data.frame(gene = c("NF1", "TP53"), stringsAsFactors = FALSE)
  expect_equal(as_candidate_set(df)[[1]]$genes, c("NF1", "TP53"))

  cs <- candidate_set(genescout_source("NF1", label = "a"))
  expect_identical(as_candidate_set(cs), cs) # passthrough, no re-wrap
})

test_that("candidate_set() accepts both varargs and a list of sources", {
  a <- genescout_source("NF1", label = "a")
  b <- genescout_source("TP53", label = "b")
  expect_equal(length(candidate_set(a, b)), 2)
  expect_equal(length(candidate_set(list(a, b))), 2)
})

test_that("dedupe_source_ids() makes colliding ids unique", {
  cs <- candidate_set(
    genescout_source("NF1", label = "My List"),
    genescout_source("TP53", label = "My List")
  )
  ids <- vapply(cs, function(s) s$id, character(1))
  expect_equal(ids, c("my-list", "my-list-2"))
})

test_that("candidate_set_to_named_lists() round-trips a named list byte-identically", {
  original <- list(mine = c("NF1", "TP53"), other = c("SUZ12"))
  expect_identical(
    candidate_set_to_named_lists(as_candidate_set(original)),
    original
  )
})

test_that("as_gene_lists() shim down-converts a candidate_set (no raw passthrough)", {
  # A candidate_set is itself a list; the old `if (is.list(x)) return(x)` would
  # have handed flatten a list of genescout_source records. The shim must dispatch
  # on class and return a clean named list of character vectors.
  cs <- candidate_set(genescout_source(c("NF1", "TP53"), label = "mine"))
  expect_identical(as_gene_lists(cs), list(mine = c("NF1", "TP53")))
  # Old named-list callers keep working.
  expect_identical(
    as_gene_lists(list(a = "NF1", b = "TP53")),
    list(a = "NF1", b = "TP53")
  )
})

test_that("flatten_candidate_set() unions tokens with per-source provenance", {
  cs <- candidate_set(
    genescout_source(c("NF1", "TP53"), label = "degs", type = "rnaseq_deg"),
    genescout_source(c("TP53"), label = "atac", type = "atacseq")
  )
  flat <- flatten_candidate_set(cs)
  expect_setequal(flat$token, c("NF1", "TP53"))
  tp53 <- which(flat$token == "TP53")
  expect_setequal(flat$input_lists[[tp53]], c("atac", "degs"))
  expect_setequal(flat$input_source_ids[[tp53]], c("atac", "degs"))
  expect_setequal(flat$input_source_types[[tp53]], c("atacseq", "rnaseq_deg"))
})

test_that("flatten_gene_lists() stays byte-identical for token + input_lists", {
  flat <- flatten_gene_lists(list(
    a = c("NF1", "", "# note", "TP53"),
    b = "TP53"
  ))
  expect_setequal(flat$token, c("NF1", "TP53"))
  expect_setequal(flat$input_lists[[which(flat$token == "TP53")]], c("a", "b"))
})

test_that("collect_candidate_set() builds from specs and drops empty sources", {
  cs <- collect_candidate_set(list(
    list(name = "degs", type = "rnaseq_deg", text = "NF1\nTP53"),
    list(name = "blank", text = "   "),
    list(name = "atac", genes = c("SUZ12"))
  ))
  expect_equal(length(cs), 2) # the blank source is dropped
  expect_equal(vapply(cs, function(s) s$label, character(1)), c("degs", "atac"))
  expect_equal(cs[[1]]$genes, c("NF1", "TP53"))
})

test_that("a candidate_set round-trips through jsonlite for a non-R frontend", {
  cs <- candidate_set(
    genescout_source(c("NF1", "TP53"), label = "degs", type = "rnaseq_deg")
  )
  json <- jsonlite::toJSON(candidate_set_to_list(cs), auto_unbox = TRUE)
  back <- candidate_set_from_list(jsonlite::fromJSON(
    json,
    simplifyVector = FALSE
  ))
  expect_s3_class(back, "genescout_candidate_set")
  expect_equal(back[[1]]$label, "degs")
  expect_equal(back[[1]]$type, "rnaseq_deg")
  expect_equal(back[[1]]$genes, c("NF1", "TP53")) # array preserved at any length
})

# Enrichment engine - flatten, resolve, dedupe, enrich, assemble (offline).
# The stub resolver + stub registry live in helper-stubs.R (shared across tests).

test_that("flatten_gene_lists() unions lists and drops blanks/comments", {
  flat <- flatten_gene_lists(list(
    a = c("NF1", "", "# note", "TP53"),
    b = c("TP53")
  ))
  expect_setequal(flat$token, c("NF1", "TP53"))
  expect_setequal(flat$input_lists[[which(flat$token == "TP53")]], c("a", "b"))
})

test_that("flatten_gene_lists() drops NA tokens without crashing", {
  # A seeded gene with a null source symbol (or an empty CSV cell) arrives as NA;
  # nzchar(NA) is TRUE and startsWith(NA, "#") is NA, so an unguarded filter would
  # keep the NA and later crash the membership lookup.
  flat <- flatten_gene_lists(list(
    seeded = c("NF1", NA_character_, "TP53"),
    other = NA_character_
  ))
  expect_setequal(flat$token, c("NF1", "TP53"))
})

test_that("resolve_genes() collapses aliases to one canonical gene", {
  flat <- flatten_gene_lists(list(mine = c("p53", "TP53", "NF1")))
  res <- resolve_genes(flat, resolver = stub_resolver)
  expect_equal(nrow(res), 2) # p53 + TP53 -> one gene, plus NF1
  tp53 <- res[res$gene_id == "ENSG00000141510", ]
  expect_setequal(tp53$input_symbols[[1]], c("p53", "TP53"))
})

test_that("resolve_genes() keeps unresolved tokens flagged, not dropped", {
  res <- resolve_genes(
    flatten_gene_lists(list(mine = "NOTAGENE")),
    resolver = stub_resolver
  )
  expect_equal(nrow(res), 1)
  expect_false(res$resolved[1])
  expect_true(startsWith(res$gene_id[1], "UNRESOLVED:"))
})

test_that("enrich_genes() + assemble_matrix() build the gene x signal matrix", {
  res <- resolve_genes(
    flatten_gene_lists(list(mine = c("NF1", "TP53"))),
    resolver = stub_resolver
  )
  reg <- stub_registry()
  enr <- enrich_genes(res, reg)
  expect_equal(nrow(enr$signals_long), 4) # 2 genes x 2 signals
  expect_setequal(unique(enr$signals_long$signal_key), c("a", "b"))

  mat <- assemble_matrix(enr$signals_long, res, reg)
  expect_equal(nrow(mat), 2)
  expect_true(all(
    c("a", "a_n", "b", "b_n", "n_sources_present") %in% names(mat)
  ))
  expect_equal(mat$n_sources_present, c(2L, 2L))
})

test_that("enrich_genes() calls the progress callback once per gene", {
  res <- resolve_genes(
    flatten_gene_lists(list(mine = c("NF1", "TP53"))),
    resolver = stub_resolver
  )
  seen <- list()
  enrich_genes(res, stub_registry(), progress = function(i, n, sym) {
    seen[[length(seen) + 1]] <<- list(i = i, n = n, sym = sym)
  })
  expect_equal(length(seen), 2) # one tick per resolved gene
  expect_equal(vapply(seen, function(x) x$i, integer(1)), 1:2)
  expect_true(all(vapply(seen, function(x) x$n, integer(1)) == 2L))
})

test_that("a missing signal is NA raw, 0 normalized, not present", {
  res <- resolve_genes(
    flatten_gene_lists(list(mine = "NF1")),
    resolver = stub_resolver
  )
  reg <- list(candid_signal(
    "z",
    "Z",
    "Stub",
    extractor = function(resolved, context = list()) signal_miss(),
    normalize = normalize_identity,
    weight = 1
  ))
  row <- enrich_genes(res, reg)$signals_long
  expect_true(is.na(row$raw))
  expect_equal(row$normalized, 0)
  expect_false(row$present)
})

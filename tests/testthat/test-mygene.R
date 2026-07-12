# MyGene client - offline parser + query-builder tests.

test_that("mygene_parse_hit() normalizes a MyGene hit", {
  hit <- read_fixture("mygene_tp53.json")$hits[[1]]
  res <- mygene_parse_hit(hit, fallback_symbol = "TP53")

  expect_true(res$ok)
  expect_equal(res$symbol, "TP53")
  expect_equal(res$entrez, "7157")
  expect_equal(res$ensembl_gene, "ENSG00000141510")
  expect_equal(res$uniprot, "P04637")
  expect_match(res$summary, "tumor suppressor")
})

test_that("mygene query helpers detect id types and clean input", {
  expect_equal(
    mygene_query_term("ENSG00000141510"),
    "ensembl.gene:ENSG00000141510"
  )
  expect_equal(mygene_query_term("7157"), "entrezgene:7157")
  expect_equal(mygene_query_term("TP53"), "TP53")
  expect_equal(mygene_clean_symbol("  TP53; "), "TP53")
  expect_null(mygene_clean_symbol("   "))
})

test_that("mygene_first() takes the first of scalar-or-list fields", {
  expect_equal(mygene_first(list("P04637", "X")), "P04637")
  expect_equal(mygene_first("P04637"), "P04637")
  expect_true(is.na(mygene_first(NULL)))
})

# --- Batch resolution (offline against a recorded /query POST array) ----------

test_that("mygene_parse_batch() maps each input symbol to its best hit, in order", {
  hits <- read_fixture("mygene_batch.json")
  res <- mygene_parse_batch(
    hits,
    c("NF1", "ENSG00000141510", "NOTAREALGENEXYZ")
  )

  expect_length(res, 3)
  expect_true(res[[1]]$ok)
  expect_equal(res[[1]]$symbol, "NF1")
  expect_equal(res[[1]]$ensembl_gene, "ENSG00000196712")
  expect_equal(res[[1]]$uniprot, "P21359")

  # An Ensembl id resolves via the id scope back to its symbol.
  expect_true(res[[2]]$ok)
  expect_equal(res[[2]]$symbol, "TP53")
  expect_equal(res[[2]]$ensembl_gene, "ENSG00000141510")

  # A `notfound` element becomes a definite miss, never a wrong gene.
  expect_false(res[[3]]$ok)
})

test_that("mygene_parse_batch() returns an aligned miss for absent or blank tokens", {
  hits <- read_fixture("mygene_batch.json")
  res <- mygene_parse_batch(hits, c("NF1", "ABSENTTOKEN", "  "))

  expect_length(res, 3) # one result per input, order preserved
  expect_true(res[[1]]$ok) # present in the array
  expect_false(res[[2]]$ok) # not returned by MyGene
  expect_false(res[[3]]$ok) # blank -> invalid identifier
  expect_match(res[[3]]$error, "valid gene identifier")
})

test_that("mygene_parse_batch() falls back to best score when no symbol matches", {
  # No hit's symbol equals the query token, so MyGene's best-score-first order wins.
  hits <- list(
    list(query = "AAA", symbol = "GENE1", ensembl = list(gene = "ENSG1")),
    list(query = "AAA", symbol = "GENE2", ensembl = list(gene = "ENSG2"))
  )
  res <- mygene_parse_batch(hits, "AAA")
  expect_equal(res[[1]]$symbol, "GENE1")
  expect_equal(res[[1]]$ensembl_gene, "ENSG1")
})

test_that("mygene_parse_batch() prefers the EXACT symbol over a higher-scored hit", {
  # Regression: querying "TTN" (alias/retired scopes) returns TTR (higher _score)
  # BEFORE TTN. The exact symbol match must win, so TTN never shows up as TTR.
  hits <- list(
    list(
      query = "TTN",
      symbol = "TTR",
      entrezgene = 7276,
      ensembl = list(gene = "ENSG00000118271")
    ),
    list(
      query = "TTN",
      symbol = "TTN",
      entrezgene = 7273,
      ensembl = list(gene = "ENSG00000155657")
    )
  )
  res <- mygene_parse_batch(hits, "TTN")
  expect_equal(res[[1]]$symbol, "TTN")
  expect_equal(res[[1]]$entrez, "7273")
  expect_equal(res[[1]]$ensembl_gene, "ENSG00000155657")
})

test_that("mygene_parse_batch() still resolves a deliberate alias (no exact match)", {
  # "p53" is nobody's official symbol, so the alias hit TP53 is correctly kept.
  hits <- list(
    list(
      query = "p53",
      symbol = "TP53",
      ensembl = list(gene = "ENSG00000141510")
    )
  )
  res <- mygene_parse_batch(hits, "p53")
  expect_equal(res[[1]]$symbol, "TP53")
})

test_that("mygene_pick_hit() matches the symbol case-insensitively, else first hit", {
  hits <- list(
    list(symbol = "TTR"),
    list(symbol = "TTN")
  )
  expect_equal(mygene_pick_hit(hits, "ttn")$symbol, "TTN") # case-insensitive
  expect_equal(mygene_pick_hit(hits, "ZZZ")$symbol, "TTR") # none match -> first
  expect_null(mygene_pick_hit(list(), "X"))
})

test_that("resolve_symbols_batch() short-circuits blank input with no network", {
  # Every token invalid -> no request, but still an aligned per-token miss.
  res <- resolve_symbols_batch(c("", "   "))
  expect_length(res, 2)
  expect_false(res[[1]]$ok)
  expect_false(res[[2]]$ok)
})

# Eval identity guard - offline. This is the CI-side protection for the TTN->TTR
# wrong-gene regression: the live evals hit APIs and don't run in CI, so the guard
# logic is exercised here on a SYNTHETIC mis-resolution instead. If the guard ever
# stops catching an input symbol that resolved to a different gene, this fails.

# A ranked-genes tibble like assemble_matrix() produces: `symbol` (resolved official
# symbol) and `gene_id` (Ensembl id, or UNRESOLVED:*). `mis` swaps TTN's row for the
# WRONG gene (TTR), reproducing the exact regression this guard exists to catch.
genes_ok <- tibble::tibble(
  symbol = c("NF1", "TP53", "TTN"),
  gene_id = c("ENSG00000196712", "ENSG00000141510", "ENSG00000155657")
)
genes_mis <- tibble::tibble(
  symbol = c("NF1", "TP53", "TTR"), # TTN silently became TTR
  gene_id = c("ENSG00000196712", "ENSG00000141510", "ENSG00000118271")
)

test_that("assert_gene_identity passes when every candidate round-trips", {
  out <- assert_gene_identity(genes_ok, c("NF1", "TP53", "TTN"))
  expect_true(out$ok)
  expect_length(out$missing, 0)
  expect_length(out$mismatched, 0)
  expect_match(out$detail, "identity OK")
})

test_that("assert_gene_identity catches an input symbol resolving to a DIFFERENT gene", {
  # The TTN->TTR regression: TTN is a candidate but the output carries TTR instead.
  out <- assert_gene_identity(genes_mis, c("NF1", "TP53", "TTN"))
  expect_false(out$ok)
  expect_equal(out$missing, "TTN")
  expect_match(out$detail, "TTN")
})

test_that("the round-trip check is case-insensitive", {
  out <- assert_gene_identity(genes_ok, c("nf1", "tp53", "ttn"))
  expect_true(out$ok)
})

test_that("expect_identity anchors the resolved Ensembl id, not just the symbol", {
  # Right symbols, but the anchor id for TTN is wrong -> a mismatch even though the
  # symbol round-trips. Catches the rarer "right symbol, wrong id" drift.
  out <- assert_gene_identity(
    genes_ok,
    c("NF1", "TTN"),
    expect_identity = list(NF1 = "ENSG00000196712", TTN = "ENSG00000000000")
  )
  expect_false(out$ok)
  expect_length(out$mismatched, 1)
  expect_match(out$mismatched, "TTN")

  # And when the anchors match the resolved ids, it passes.
  ok <- assert_gene_identity(
    genes_ok,
    c("NF1", "TTN"),
    expect_identity = list(NF1 = "ENSG00000196712", TTN = "ENSG00000155657")
  )
  expect_true(ok$ok)
})

test_that("expect_identity flags an anchor gene that is absent from the result", {
  out <- assert_gene_identity(
    genes_mis, # has no TTN row at all (it became TTR)
    c("NF1", "TP53", "TTN"),
    expect_identity = list(TTN = "ENSG00000155657")
  )
  expect_false(out$ok)
  # TTN is both a round-trip miss AND an anchor mismatch (absent id).
  expect_equal(out$missing, "TTN")
  expect_match(out$mismatched, "absent")
})

test_that("identity_missing_symbols ignores blank/NA candidates", {
  expect_length(identity_missing_symbols(genes_ok, c("NF1", "", NA)), 0)
})

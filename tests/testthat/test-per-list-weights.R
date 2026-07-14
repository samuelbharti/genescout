# Per-list trust weights modulate the cross-source corroboration signal. The key
# invariants: default (all-1) weights are byte-identical to the unweighted signal,
# raising a corroborating source's weight raises the gene's normalized value, and a
# high weight can never manufacture corroboration from a single source.

make_resolved <- function() {
  tibble::tibble(
    gene_id = c("g1", "g2"),
    symbol = c("AAA", "BBB"),
    # AAA is in two of the user's sources; BBB is in one only.
    input_lists = list(c("rna", "wes"), c("wes"))
  )
}

test_that("default (all-1) weights are identical to the unweighted signal", {
  reg <- list(cross_source_signal())
  resolved <- make_resolved()
  ctx <- list(user_sources = c("wes", "rna"))
  base <- enrich_input_signals(resolved, reg, context = ctx)$signals_long
  eq1 <- enrich_input_signals(
    resolved,
    reg,
    context = c(ctx, list(source_weights = list(wes = 1, rna = 1)))
  )$signals_long
  expect_equal(base, eq1)
})

test_that("a corroborated gene is present; a lone-source gene is not", {
  reg <- list(cross_source_signal())
  resolved <- make_resolved()
  ctx <- list(user_sources = c("wes", "rna"))
  s <- enrich_input_signals(resolved, reg, context = ctx)$signals_long
  a <- s[s$symbol == "AAA", ]
  b <- s[s$symbol == "BBB", ]
  expect_equal(a$raw, 2)
  expect_true(a$present)
  expect_gt(a$normalized, 0)
  expect_equal(b$raw, 1)
  expect_false(b$present)
})

test_that("higher per-list weights raise the corroborated gene's value", {
  reg <- list(cross_source_signal())
  resolved <- make_resolved()
  ctx <- list(user_sources = c("wes", "rna"))
  base <- enrich_input_signals(resolved, reg, context = ctx)$signals_long
  up <- enrich_input_signals(
    resolved,
    reg,
    context = c(ctx, list(source_weights = list(wes = 2, rna = 2)))
  )$signals_long
  a0 <- base[base$symbol == "AAA", ]
  a1 <- up[up$symbol == "AAA", ]
  expect_equal(a1$raw, 4) # 2 sources x weight 2
  expect_gt(a1$normalized, a0$normalized)
})

test_that("a high weight cannot manufacture corroboration from one source", {
  reg <- list(cross_source_signal())
  resolved <- make_resolved()
  ctx <- list(user_sources = c("wes", "rna"))
  base <- enrich_input_signals(resolved, reg, context = ctx)$signals_long
  up <- enrich_input_signals(
    resolved,
    reg,
    context = c(ctx, list(source_weights = list(wes = 5, rna = 5)))
  )$signals_long
  b0 <- base[base$symbol == "BBB", ]
  b1 <- up[up$symbol == "BBB", ]
  expect_equal(b1$raw, 1) # lone source stays raw 1 regardless of weight
  expect_false(b1$present)
  expect_equal(b1$normalized, b0$normalized) # still neutral
})

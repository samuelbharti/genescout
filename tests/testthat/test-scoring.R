# Composite ranking - normalization, weighting, deterministic rank (offline).

test_that("normalize_identity() clamps to [0,1] and maps NA to 0", {
  expect_equal(normalize_identity(c(0.3, -1, 2, NA)), c(0.3, 0, 1, 0))
})

test_that("normalize_saturating(m) hits 0.5 at x = m and 0 at 0/NA", {
  f <- normalize_saturating(5)
  expect_equal(f(5), 0.5)
  expect_equal(f(0), 0)
  expect_equal(f(NA), 0)
  expect_true(f(50) > f(5))
})

test_that("normalize_log_saturating(m) is monotone and bounded in [0,1)", {
  f <- normalize_log_saturating(50)
  expect_equal(f(0), 0)
  expect_true(f(50) > 0 && f(50) < 1)
  expect_true(f(1000) > f(50))
  expect_true(all(f(c(1, 10, 100, 1000)) < 1))
})

test_that("compute_composite() is the weighted mean of normalized signals", {
  registry <- list(
    list(key = "a", weight = 1),
    list(key = "b", weight = 0.5),
    list(key = "c", weight = 1)
  )
  gm <- tibble::tibble(
    symbol = c("BROAD", "FAMOUS"),
    a_n = c(0.5, 0.0),
    b_n = c(0.5, 1.0),
    c_n = c(0.5, 0.0),
    n_sources_present = c(3L, 1L)
  )
  out <- compute_composite(gm, registry, coverage_bonus = FALSE)
  # BROAD: (1*.5 + .5*.5 + 1*.5)/2.5 = 0.5 ; FAMOUS: (.5*1)/2.5 = 0.2
  expect_equal(out$composite, c(0.5, 0.2))
})

test_that("rank_genes() ranks broad-moderate above single-source-famous", {
  # The anti-bias property, encoded: breadth beats a single loud source.
  gm <- tibble::tibble(symbol = c("FAMOUS", "BROAD"), composite = c(0.2, 0.5))
  ranked <- rank_genes(gm)
  expect_equal(ranked$symbol[1], "BROAD")
  expect_equal(ranked$rank, c(1, 2))
})

test_that("grade_for_score() is vectorized with NA handling", {
  expect_equal(
    grade_for_score(c(0.6, 0.3, 0.1, NA)),
    c("High", "Moderate", "Low", "Insufficient")
  )
})

test_that("load_rubric() reads the default profile weights", {
  rubric <- load_rubric(test_path("..", "..", "rubric.yml"))
  expect_true(is.numeric(rubric$weights$ot_assoc))
  expect_true(is.numeric(rubric$midpoints$clinvar_path))
})

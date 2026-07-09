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

test_that("normalize_saturating_desc(m): 1 at x=0, 0.5 at x=m, lower x scores up", {
  f <- normalize_saturating_desc(0.35)
  expect_equal(f(0), 1)
  expect_equal(f(0.35), 0.5)
  expect_equal(f(NA), 0)
  expect_true(f(0.1) > f(1.0)) # lower LOEUF (more constrained) -> higher score
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

test_that("compute_composite() does not penalize a missing annotation signal", {
  registry <- list(
    list(key = "ev1", weight = 1, role = "evidence"),
    list(key = "ann", weight = 1, role = "annotation")
  )
  gm <- tibble::tibble(
    symbol = c("HAS_ANN", "NO_ANN"),
    ev1_n = c(0.5, 0.5),
    ann_n = c(0.8, 0),
    ev1_present = c(TRUE, TRUE),
    ann_present = c(TRUE, FALSE),
    n_evidence_present = c(1L, 1L)
  )
  out <- compute_composite(gm, registry)
  # HAS_ANN: (1*.5 + 1*.8)/(1+1) = 0.65 ; NO_ANN: (1*.5)/1 = 0.5
  # (the absent annotation weight stays OUT of NO_ANN's denominator).
  expect_equal(out$composite, c(0.65, 0.5))
})

test_that("compute_composite() honors a named weights override", {
  registry <- list(
    list(key = "a", weight = 1, role = "evidence"),
    list(key = "b", weight = 1, role = "evidence")
  )
  gm <- tibble::tibble(a_n = 1.0, b_n = 0.0)
  base <- compute_composite(gm, registry)$composite
  up <- compute_composite(gm, registry, weights = c(a = 3, b = 1))$composite
  expect_equal(base, 0.5) # (1*1 + 1*0)/2
  expect_equal(up, 0.75) # (3*1 + 1*0)/4
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

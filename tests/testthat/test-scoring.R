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

test_that("normalize_corroboration(m): 1 source is neutral, breadth saturates", {
  f <- normalize_corroboration(1)
  expect_equal(f(1), 0) # one source: no bonus, never sub-baseline
  expect_equal(f(2), 0.5)
  expect_equal(f(3), 2 / 3)
  expect_equal(f(NA), 0)
  expect_equal(f(0), 0)
  expect_true(f(4) > f(3)) # monotone in breadth
  expect_true(all(f(2:100) < 1)) # bounded below 1
})

test_that("cross-source is Balanced: breadth beats a loud source, capped below High", {
  # Inline rubric so the test is independent of the working directory; the
  # unspecified weights fall back to their code defaults (matching rubric.yml).
  rubric <- list(
    weights = list(cross_source = 2),
    midpoints = list(cross_source = 1)
  )
  reg <- candid_signal_registry(rubric = rubric, multi_source = TRUE)
  keys <- vapply(reg, function(s) s$key, character(1))
  # A one-gene matrix row from a named list of normalized values (0 elsewhere).
  mk <- function(vals) {
    row <- tibble::tibble(symbol = "X")
    for (k in keys) {
      v <- vals[[k]] %||% 0
      row[[paste0(k, "_n")]] <- v
      row[[paste0(k, "_present")]] <- v > 0
    }
    row
  }
  norm3 <- normalize_corroboration(1)(3) # a gene in 3 user sources
  loud <- mk(list(ot_assoc = 1)) # one strong external association
  broad <- mk(list(cross_source = norm3)) # breadth across 3 sources, nothing else
  capped <- mk(list(cross_source = 1)) # breadth fully saturated
  scored <- compute_composite(dplyr::bind_rows(loud, broad, capped), reg)

  # Breadth across 3 of the user's own sources out-ranks a single loud source ...
  expect_gt(scored$composite[2], scored$composite[1])
  # ... but stays Moderate (external evidence is still required for a High grade) ...
  expect_equal(grade_for_score(scored$composite[2]), "Moderate")
  # ... and breadth ALONE can never reach the High threshold, even saturated.
  expect_lt(scored$composite[3], CANDID_GRADE_BREAKS[["high"]])
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

test_that("a present but weak annotation never lowers the composite", {
  # The "never penalize" invariant: a gene with identical evidence plus a WEAK
  # annotation must not rank below one that simply lacks the annotation.
  registry <- list(
    list(key = "ev1", weight = 1, role = "evidence"),
    list(key = "ann", weight = 1, role = "annotation")
  )
  gm <- tibble::tibble(
    symbol = c("WEAK_ANN", "NO_ANN"),
    ev1_n = c(0.6, 0.6),
    ann_n = c(0.25, 0), # present-but-weak (0.25 < evidence mean 0.6) vs absent
    ev1_present = c(TRUE, TRUE),
    ann_present = c(TRUE, FALSE),
    n_evidence_present = c(1L, 1L)
  )
  out <- compute_composite(gm, registry)
  # The weak annotation is below the evidence-only mean, so it is neutral: both
  # genes score the evidence-only 0.6 and WEAK_ANN is not demoted below NO_ANN.
  expect_equal(out$composite, c(0.6, 0.6))
})

test_that("a present strong annotation raises the composite", {
  registry <- list(
    list(key = "ev1", weight = 1, role = "evidence"),
    list(key = "ann", weight = 1, role = "annotation")
  )
  gm <- tibble::tibble(
    symbol = c("STRONG_ANN", "NO_ANN"),
    ev1_n = c(0.6, 0.6),
    ann_n = c(0.9, 0), # strong (>= evidence mean) vs absent
    ev1_present = c(TRUE, TRUE),
    ann_present = c(TRUE, FALSE),
    n_evidence_present = c(1L, 1L)
  )
  out <- compute_composite(gm, registry)
  # STRONG_ANN: (0.6 + 0.9)/2 = 0.75 (raised); NO_ANN: 0.6 (unchanged).
  expect_equal(out$composite, c(0.75, 0.6))
  expect_true(out$composite[1] > out$composite[2])
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

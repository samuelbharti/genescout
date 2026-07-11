# Caveats & veto - deterministic anti-bias override (offline, no network).

# A tiny two-evidence-signal registry for building gene matrices.
caveat_registry <- function() {
  list(
    candid_signal(
      "ev1",
      "Evidence one",
      "Src",
      function(resolved, context = list()) signal_miss(),
      normalize_identity,
      1,
      role = "evidence"
    ),
    candid_signal(
      "ev2",
      "Evidence two",
      "Src",
      function(resolved, context = list()) signal_miss(),
      normalize_identity,
      1,
      role = "evidence"
    )
  )
}

# An explicit rubric so caveat behavior does not depend on the working directory.
caveat_test_rubric <- function() {
  list(
    caveats = list(
      enabled = TRUE,
      flags_genes = c("TTN", "MUC16"),
      single_source = list(penalty = 0.5, max_norm = 0.5),
      common_variant = list(penalty = 0.8, min_af = 0.001)
    )
  )
}

test_that("apply_caveats() vetoes a FLAGS gene and records the reason", {
  gm <- tibble::tibble(
    symbol = c("NF1", "TTN"),
    composite = c(0.7, 0.6),
    n_evidence_present = c(2L, 2L),
    ev1_present = c(TRUE, TRUE),
    ev1_n = c(0.7, 0.6),
    ev2_present = c(TRUE, TRUE),
    ev2_n = c(0.7, 0.6)
  )
  out <- apply_caveats(gm, caveat_registry(), rubric = caveat_test_rubric())
  expect_true(out$vetoed[out$symbol == "TTN"])
  expect_false(out$vetoed[out$symbol == "NF1"])
  expect_match(out$caveats[[which(out$symbol == "TTN")]][1], "FLAGS")
  # A veto leaves the composite untouched (rank_genes handles the ordering).
  expect_equal(out$composite[out$symbol == "TTN"], 0.6)
})

test_that("apply_caveats() down-weights a single weak evidence source", {
  gm <- tibble::tibble(
    symbol = "LONE",
    composite = 0.4,
    n_evidence_present = 1L,
    ev1_present = TRUE,
    ev1_n = 0.3, # < max_norm 0.5 -> weak
    ev2_present = FALSE,
    ev2_n = 0
  )
  out <- apply_caveats(gm, caveat_registry(), rubric = caveat_test_rubric())
  expect_equal(out$composite, 0.2) # 0.4 * penalty 0.5
  expect_false(out$vetoed[1])
  expect_match(out$caveats[[1]][1], "single weak source")
})

test_that("apply_caveats() leaves a single STRONG source and multi-source clean", {
  gm <- tibble::tibble(
    symbol = c("STRONG1", "BROAD"),
    composite = c(0.6, 0.6),
    n_evidence_present = c(1L, 2L),
    ev1_present = c(TRUE, TRUE),
    ev1_n = c(0.8, 0.5), # STRONG1's lone source is >= max_norm
    ev2_present = c(FALSE, TRUE),
    ev2_n = c(0, 0.5)
  )
  out <- apply_caveats(gm, caveat_registry(), rubric = caveat_test_rubric())
  expect_equal(out$composite, c(0.6, 0.6)) # neither down-weighted
  expect_equal(lengths(out$caveats), c(0L, 0L))
})

test_that("apply_caveats() down-weights a gene with a common gnomAD LoF variant", {
  gm <- tibble::tibble(
    symbol = c("COMMON", "RARE"),
    composite = c(0.6, 0.6),
    n_evidence_present = c(2L, 2L),
    ev1_present = c(TRUE, TRUE),
    ev1_n = c(0.6, 0.6),
    ev2_present = c(TRUE, TRUE),
    ev2_n = c(0.6, 0.6),
    # COMMON carries a 2% pLoF variant; RARE has a real 0 (present, no common pLoF).
    gnomad_af = c(0.02, 0.0),
    gnomad_af_present = c(TRUE, TRUE)
  )
  out <- apply_caveats(gm, caveat_registry(), rubric = caveat_test_rubric())
  expect_equal(out$composite[out$symbol == "COMMON"], 0.48) # 0.6 * 0.8
  expect_equal(out$composite[out$symbol == "RARE"], 0.6) # 0 AF < min_af -> clean
  expect_match(
    out$caveats[[which(out$symbol == "COMMON")]][1],
    "Common loss-of-function"
  )
  expect_length(out$caveats[[which(out$symbol == "RARE")]], 0)
})

test_that("the common-variant caveat is silent when the gnomAD-AF signal is absent", {
  # No gnomad_af columns (the opt-in signal did not run) -> the trigger must not fire.
  gm <- tibble::tibble(
    symbol = "GENE",
    composite = 0.6,
    n_evidence_present = 2L,
    ev1_present = TRUE,
    ev1_n = 0.6,
    ev2_present = TRUE,
    ev2_n = 0.6
  )
  out <- apply_caveats(gm, caveat_registry(), rubric = caveat_test_rubric())
  expect_equal(out$composite, 0.6)
  expect_length(out$caveats[[1]], 0)
})

test_that("apply_caveats() extends the FLAGS set with disease-context priors", {
  gm <- tibble::tibble(
    symbol = "CTXGENE",
    composite = 0.6,
    n_evidence_present = 2L,
    ev1_present = TRUE,
    ev1_n = 0.6,
    ev2_present = TRUE,
    ev2_n = 0.6
  )
  ctx <- list(priors = list(flags_genes = c("CTXGENE")))
  out <- apply_caveats(
    gm,
    caveat_registry(),
    context = ctx,
    rubric = caveat_test_rubric()
  )
  expect_true(out$vetoed[1])
})

test_that("apply_caveats(enabled = FALSE) adds empty columns and does nothing", {
  gm <- tibble::tibble(
    symbol = "TTN",
    composite = 0.6,
    n_evidence_present = 1L,
    ev1_present = TRUE,
    ev1_n = 0.1,
    ev2_present = FALSE,
    ev2_n = 0
  )
  out <- apply_caveats(
    gm,
    caveat_registry(),
    rubric = caveat_test_rubric(),
    enabled = FALSE
  )
  expect_false(any(out$vetoed))
  expect_equal(lengths(out$caveats), 0L)
  expect_equal(out$composite, 0.6) # no down-weight
})

test_that("apply_caveats() is reproducible (same input -> identical output)", {
  gm <- tibble::tibble(
    symbol = c("TTN", "LONE", "NF1"),
    composite = c(0.9, 0.4, 0.7),
    n_evidence_present = c(2L, 1L, 2L),
    ev1_present = c(TRUE, TRUE, TRUE),
    ev1_n = c(0.9, 0.3, 0.7),
    ev2_present = c(TRUE, FALSE, TRUE),
    ev2_n = c(0.9, 0, 0.7)
  )
  a <- apply_caveats(gm, caveat_registry(), rubric = caveat_test_rubric())
  b <- apply_caveats(gm, caveat_registry(), rubric = caveat_test_rubric())
  expect_identical(a, b)
})

test_that("rank_result() sinks a vetoed gene to the bottom with grade Vetoed", {
  enriched <- list(
    registry_obj = caveat_registry(),
    context = list(),
    genes = tibble::tibble(
      gene_id = c("g1", "g2"),
      symbol = c("NF1", "TTN"),
      resolved = c(TRUE, TRUE),
      input_lists = list("a", "a"),
      ev1 = c(0.8, 0.9),
      ev1_n = c(0.8, 0.9),
      ev1_present = c(TRUE, TRUE),
      ev2 = c(0.8, 0.9),
      ev2_n = c(0.8, 0.9),
      ev2_present = c(TRUE, TRUE),
      n_sources_present = c(2L, 2L),
      n_evidence_present = c(2L, 2L)
    )
  )
  res <- rank_result(enriched)
  ttn <- res$genes[res$genes$symbol == "TTN", ]
  nf1 <- res$genes[res$genes$symbol == "NF1", ]
  # TTN's raw composite (0.9) is HIGHER than NF1's (0.8), yet the veto sinks it.
  expect_true(ttn$vetoed)
  expect_equal(ttn$grade, "Vetoed")
  expect_equal(nf1$rank, 1)
  expect_true(ttn$rank > nf1$rank)
})

test_that("rank_result(caveats = FALSE) disables the veto", {
  enriched <- list(
    registry_obj = caveat_registry(),
    context = list(),
    genes = tibble::tibble(
      gene_id = c("g1", "g2"),
      symbol = c("NF1", "TTN"),
      resolved = c(TRUE, TRUE),
      input_lists = list("a", "a"),
      ev1 = c(0.8, 0.9),
      ev1_n = c(0.8, 0.9),
      ev1_present = c(TRUE, TRUE),
      ev2 = c(0.8, 0.9),
      ev2_n = c(0.8, 0.9),
      ev2_present = c(TRUE, TRUE),
      n_sources_present = c(2L, 2L),
      n_evidence_present = c(2L, 2L)
    )
  )
  res <- rank_result(enriched, caveats = FALSE)
  ttn <- res$genes[res$genes$symbol == "TTN", ]
  expect_false(ttn$vetoed)
  # Without the veto, TTN's higher composite ranks it first.
  expect_equal(ttn$rank, 1)
})

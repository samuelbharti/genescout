# Citation gate - offline tests over synthetic evidence (no network, no LLM).

# Synthetic normalized evidence: two grounded pathway-disease rows + one
# ungrounded literature row (empty source_id) that the gate should drop.
make_evidence <- function() {
  evidence_tibble(
    domain = c("pathway-disease", "pathway-disease", "literature"),
    title = c(
      "Li-Fraumeni syndrome",
      "hepatocellular carcinoma",
      "ungrounded paper"
    ),
    detail = c("score 0.88", "score 0.80", "Journal (2020)"),
    score = c(0.88, 0.80, NA_real_),
    source_id = c(
      "OpenTargets:ENSG:MONDO_0018875",
      "OpenTargets:ENSG:MONDO_0007256",
      ""
    ),
    source_url = c("https://x", "https://y", "")
  )
}

test_that("validate_evidence() keeps grounded rows and rejects the rest", {
  gated <- validate_evidence(make_evidence())
  expect_equal(nrow(gated$kept), 2)
  expect_equal(nrow(gated$rejected), 1)
  expect_true(all(nzchar(gated$kept$source_id)))
})

test_that("validate_evidence() handles empty evidence", {
  empty <- make_evidence()[0, ]
  gated <- validate_evidence(empty)
  expect_equal(nrow(gated$kept), 0)
})

test_that("validate_signals() demotes a present-but-ungrounded signal to a miss", {
  sig <- tibble::tibble(
    gene_id = c("ENSG1", "ENSG2", "ENSG3"),
    symbol = c("A", "B", "C"),
    signal_key = "ot_assoc",
    label = "Open Targets",
    raw = c(0.9, 0.7, NA_real_),
    normalized = c(0.9, 0.7, NA_real_),
    present = c(TRUE, TRUE, FALSE),
    source_id = c("OpenTargets:1", "", ""),
    source_url = ""
  )
  out <- validate_signals(sig)
  expect_equal(out$n_ungrounded, 1L)
  # The grounded row is untouched.
  expect_true(out$signals$present[1])
  expect_equal(out$signals$raw[1], 0.9)
  # The ungrounded one reads exactly like "no data": no value, not present.
  expect_false(out$signals$present[2])
  expect_true(is.na(out$signals$raw[2]))
  expect_true(is.na(out$signals$normalized[2]))
  # An honest miss already had no source_id and is not counted as a violation.
  expect_false(out$signals$present[3])
})

test_that("validate_signals() keeps the table's shape so the matrix is unchanged", {
  sig <- tibble::tibble(
    gene_id = c("ENSG1", "ENSG2"),
    symbol = c("A", "B"),
    signal_key = "ot_assoc",
    label = "Open Targets",
    raw = c(0.9, 0.7),
    normalized = c(0.9, 0.7),
    present = c(TRUE, TRUE),
    source_id = c("", ""),
    source_url = ""
  )
  out <- validate_signals(sig)
  # Rows are demoted, never dropped: assemble_matrix() builds one cell per
  # (gene x signal) from this table.
  expect_equal(nrow(out$signals), 2)
  expect_equal(out$n_ungrounded, 2L)
})

test_that("validate_signals() handles empty input", {
  empty <- tibble::tibble(
    gene_id = character(),
    present = logical(),
    raw = numeric(),
    normalized = numeric(),
    source_id = character()
  )
  out <- validate_signals(empty)
  expect_equal(nrow(out$signals), 0)
  expect_equal(out$n_ungrounded, 0L)
})

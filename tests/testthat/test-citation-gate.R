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

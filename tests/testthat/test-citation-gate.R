# Citation gate + scoring + report assembly - offline tests over synthetic
# evidence (no network, no LLM).

make_evidence <- function() {
  tibble::tibble(
    disease = c(
      "Li-Fraumeni syndrome",
      "hepatocellular carcinoma",
      "ungrounded"
    ),
    disease_id = c("MONDO_0018875", "MONDO_0007256", NA_character_),
    score = c(0.88, 0.80, 0.10),
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

test_that("score_candidate() grades by the best association score", {
  ctx <- list(known_drivers = c("TP53"))
  scored <- score_candidate(make_evidence()[1:2, ], ctx, symbol = "TP53")
  expect_equal(scored$grade, "High")
  expect_true(scored$is_driver)

  none <- score_candidate(make_evidence()[0, ], ctx, symbol = "TP53")
  expect_equal(none$grade, "Insufficient evidence")
})

test_that("render_report() writes a self-contained HTML citing sources", {
  result <- list(
    context = list(id = "nf1", label = "NF1"),
    candidates = list(list(
      candidate = "TP53",
      symbol = "TP53",
      ok = TRUE,
      grade = "High",
      score = 0.88,
      rationale = "Top score 0.88.",
      evidence = make_evidence()[1:2, ],
      caveats = character(),
      next_step = "Validate top association.",
      narrative = NA_character_
    )),
    ranked = data.frame(
      symbol = "TP53",
      grade = "High",
      score = 0.88,
      top_disease = "Li-Fraumeni syndrome",
      n_evidence = 2L,
      stringsAsFactors = FALSE
    ),
    provenance = list(list(source = "Open Targets Platform")),
    generated_with_llm = FALSE
  )
  out <- tempfile(fileext = ".html")
  on.exit(unlink(out), add = TRUE)
  render_report(result, out)

  expect_true(file.exists(out))
  html <- paste(readLines(out, warn = FALSE), collapse = "\n")
  expect_match(html, "Li-Fraumeni syndrome")
  expect_match(html, "OpenTargets:ENSG:MONDO_0018875")
  expect_match(html, "Research use only")
})

test_that("render_candidate_cards() returns UI with grounded citations", {
  cand <- list(list(
    candidate = "TP53", symbol = "TP53", ok = TRUE, grade = "High",
    score = 0.88, rationale = "Top score 0.88.",
    evidence = make_evidence()[1:2, ], caveats = "a caveat",
    next_step = "Validate.", narrative = NA_character_
  ))
  cards <- render_candidate_cards(cand)
  expect_s3_class(cards, "shiny.tag.list")
  rendered <- as.character(cards)
  expect_match(rendered, "card")
  expect_match(rendered, "OpenTargets:ENSG:MONDO_0018875")
})

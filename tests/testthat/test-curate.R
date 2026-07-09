# AI curator - grounding gate, fallback, and a stubbed-model path (offline).

fake_curate_result <- function() {
  genes <- tibble::tibble(
    rank = 1:3,
    gene_id = c("ENSG1", "ENSG2", "ENSG3"),
    symbol = c("NF1", "TP53", "TTN"),
    composite = c(0.8, 0.5, 0.1),
    grade = c("High", "Moderate", "Low"),
    ot_assoc = c(0.9, 0.5, NA_real_)
  )
  evidence <- evidence_long_rows(
    "ENSG1",
    "ot_assoc",
    "pathway-disease",
    "NF1 association",
    "score 0.90",
    0.9,
    "OpenTargets:ENSG1:MONDO_x",
    "https://x"
  )
  registry <- tibble::tibble(
    key = "ot_assoc",
    label = "Open Targets association",
    source = "Open Targets",
    weight = 1,
    role = "evidence",
    direction = "higher_better"
  )
  list(
    description = "NF1-associated MPNST study",
    genes = genes,
    evidence = evidence,
    registry = registry,
    context = list(),
    generated_with_llm = FALSE
  )
}

test_that("validate_curation() drops hallucinated symbols and de-duplicates", {
  df <- tibble::tibble(
    gene_symbol = c("NF1", "FAKE", "nf1"),
    include = c(TRUE, TRUE, TRUE),
    confidence = c(0.9, 0.8, 0.5),
    rationale = c("a", "b", "c")
  )
  out <- validate_curation(df, c("NF1", "TP53"))
  expect_equal(out$gene_symbol, "NF1") # FAKE dropped, duplicate nf1 removed
})

test_that("validate_curation() clamps confidence and coerces an NA include", {
  df <- tibble::tibble(
    gene_symbol = c("NF1", "TP53"),
    include = c(TRUE, NA),
    confidence = c(5, 0.3)
  )
  out <- validate_curation(df, c("NF1", "TP53"))
  expect_equal(out$confidence, c(1, 0.3)) # 5 clamped to 1
  expect_equal(out$include, c(TRUE, FALSE)) # NA include value -> FALSE
})

test_that("fallback_curation() takes the top-N by composite rank", {
  fb <- fallback_curation(fake_curate_result(), 2)
  expect_equal(fb$gene_symbol, c("NF1", "TP53"))
  expect_true(all(fb$include))
  expect_match(fb$rationale[1], "composite rank")
})

test_that("selections_to_df() coerces a list-of-lists", {
  sel <- list(
    list(
      gene_symbol = "NF1",
      include = TRUE,
      confidence = 0.9,
      rationale = "x"
    ),
    list(
      gene_symbol = "TP53",
      include = FALSE,
      confidence = 0.2,
      rationale = "y"
    )
  )
  df <- selections_to_df(sel)
  expect_equal(df$gene_symbol, c("NF1", "TP53"))
  expect_equal(df$include, c(TRUE, FALSE))
})

test_that("build_curation_prompt() grounds on the shown evidence + context", {
  res <- fake_curate_result()
  p <- build_curation_prompt(res, curation_candidates(res, 3), 40)
  expect_match(p$system, "ONLY from the provided candidate list", fixed = TRUE)
  expect_match(p$user, "NF1")
  expect_match(p$user, "OpenTargets:ENSG1:MONDO_x") # evidence source id shown
  expect_match(p$user, "NF1-associated MPNST study") # the study description
})

test_that("curate_gene_list() falls back (with the error) when the model throws", {
  res <- fake_curate_result()
  cur <- curate_gene_list(
    res,
    config = candid_config,
    chat_factory = function(system_prompt) stop("boom")
  )
  expect_false(attr(cur, "ai_used"))
  expect_true(nrow(cur) >= 1) # fell back to rank
  expect_match(attr(cur, "error"), "boom")
})

test_that("curate_gene_list() uses a stubbed model and drops hallucinations", {
  skip_if_not_installed("ellmer")
  res <- fake_curate_result()
  sel <- list(
    list(
      gene_symbol = "NF1",
      include = TRUE,
      confidence = 0.95,
      rationale = "s"
    ),
    list(
      gene_symbol = "GHOST",
      include = TRUE,
      confidence = 0.9,
      rationale = "x"
    )
  )
  factory <- function(system_prompt) {
    list(chat_structured = function(user, type) {
      list(selections = sel, overall_notes = "n")
    })
  }
  cur <- curate_gene_list(res, config = candid_config, chat_factory = factory)
  expect_true(attr(cur, "ai_used"))
  expect_equal(cur$gene_symbol, "NF1") # GHOST not a candidate -> dropped
})

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

test_that("selections_to_df() carries a source_ids list-column", {
  sel <- list(
    list(
      gene_symbol = "NF1",
      include = TRUE,
      confidence = 0.9,
      rationale = "x",
      source_ids = list("PMID:1", "PMID:2")
    ),
    list(
      gene_symbol = "TP53",
      include = FALSE,
      confidence = 0.2,
      rationale = "y"
    )
  )
  df <- selections_to_df(sel)
  expect_equal(df$source_ids[[1]], c("PMID:1", "PMID:2"))
  expect_equal(df$source_ids[[2]], character()) # no ids -> empty, never NA
})

test_that("validate_curation() grounds cited source_ids to the gene's evidence", {
  df <- tibble::tibble(
    gene_symbol = "NF1",
    include = TRUE,
    confidence = 0.9,
    rationale = "x",
    source_ids = list(c("PMID:1", "PMID:FAKE"))
  )
  ev_ids <- list(NF1 = c("PMID:1", "PMID:2"))
  out <- validate_curation(df, "NF1", ev_ids)
  # PMID:1 is real evidence for NF1 and kept; the fabricated PMID:FAKE is dropped.
  expect_equal(out$source_ids[[1]], "PMID:1")
})

test_that("curation_evidence_ids() maps a symbol to its gathered evidence ids", {
  res <- fake_curate_result()
  m <- curation_evidence_ids(res, curation_candidates(res, 3))
  expect_equal(m[["NF1"]], "OpenTargets:ENSG1:MONDO_x")
  expect_equal(m[["TP53"]], character()) # TP53 (ENSG2) has no evidence in fixture
})

test_that("fallback_curation() grounds source_ids from the gene's own evidence", {
  fb <- fallback_curation(fake_curate_result(), 2)
  expect_equal(fb$source_ids[[1]], "OpenTargets:ENSG1:MONDO_x") # NF1's evidence
  expect_equal(fb$source_ids[[2]], character()) # TP53 has none
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
    config = genescout_config,
    chat_factory = function(system_prompt) stop("boom")
  )
  expect_false(attr(cur, "ai_used"))
  expect_true(nrow(cur) >= 1) # fell back to rank
  expect_match(attr(cur, "error"), "boom")
})

test_that("cap_curation() keeps the target's most-confident included genes", {
  df <- tibble::tibble(
    gene_symbol = c("A", "B", "C", "D"),
    include = c(TRUE, TRUE, TRUE, FALSE),
    confidence = c(0.9, 0.4, 0.7, 0.99)
  )
  out <- cap_curation(df, 2)
  # Among the 3 included, keep the 2 most confident (A=0.9, C=0.7); B dropped.
  expect_equal(which(out$include), c(1L, 3L))
  # D was already excluded and stays excluded (a high confidence does not resurrect it).
  expect_false(out$include[4])
})

test_that("cap_curation() is a no-op when the included count is within target", {
  df <- tibble::tibble(
    gene_symbol = c("A", "B"),
    include = c(TRUE, FALSE),
    confidence = c(0.5, 0.9)
  )
  expect_identical(cap_curation(df, 5), df)
})

test_that("curate_gene_list() caps the AI selection to the target size", {
  skip_if_not_installed("ellmer")
  res <- fake_curate_result() # candidates NF1, TP53, TTN
  sel <- list(
    list(
      gene_symbol = "NF1",
      include = TRUE,
      confidence = 0.9,
      rationale = "a"
    ),
    list(
      gene_symbol = "TP53",
      include = TRUE,
      confidence = 0.6,
      rationale = "b"
    ),
    list(gene_symbol = "TTN", include = TRUE, confidence = 0.8, rationale = "c")
  )
  factory <- function(system_prompt) {
    list(chat_structured = function(user, type) {
      list(selections = sel, overall_notes = "n")
    })
  }
  cur <- curate_gene_list(
    res,
    config = genescout_config,
    top_n = 2,
    chat_factory = factory
  )
  inc <- cur$gene_symbol[which(cur$include)]
  expect_length(inc, 2) # capped to the target of 2
  expect_setequal(inc, c("NF1", "TTN")) # the two most confident (0.9, 0.8)
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
  cur <- curate_gene_list(
    res,
    config = genescout_config,
    chat_factory = factory
  )
  expect_true(attr(cur, "ai_used"))
  expect_equal(cur$gene_symbol, "NF1") # GHOST not a candidate -> dropped
})

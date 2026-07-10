# Interpretive input agent - grounding gate, fallback, confirm, biogate seam
# (offline; the model is stubbed via an injected chat_factory).

# read_prompt() resolves prompts/ relative to the app root, but tests run from
# tests/testthat; run the prompt-loading paths from the app root.
with_app_root <- function(code) {
  withr::with_dir(testthat::test_path("..", ".."), code)
}

test_that("validate_input_curation() gates on the ORIGINAL token, not the symbol", {
  df <- tibble::tibble(
    original = c("nf1", "TPP53", "GHOST"),
    symbol = c("NF1", "TP53", "MADEUP"),
    action = c("correct", "correct", "keep"),
    reason = c("alias", "typo", "x"),
    confidence = c(0.9, 0.95, 0.5)
  )
  out <- validate_input_curation(df, provided = c("nf1", "TPP53"))
  # GHOST is not a provided token -> dropped (the agent cannot invent a gene) ...
  expect_setequal(out$original, c("nf1", "TPP53"))
  # ... but a typo correction whose symbol is off-list legitimately survives.
  expect_equal(out$symbol[out$original == "TPP53"], "TP53")
})

test_that("validate_input_curation() reconciles omitted tokens and coerces actions", {
  out <- validate_input_curation(
    tibble::tibble(
      original = c("NF1", "header"),
      symbol = c("NF1", "XYZ"),
      action = c("weird", "drop"),
      reason = c("", "not a gene"),
      confidence = c(NA, NA)
    ),
    provided = c("NF1", "header", "SUZ12")
  )
  expect_equal(out$action[out$original == "NF1"], "flag") # unknown action -> flag
  expect_true(is.na(out$symbol[out$original == "header"])) # drop clears the symbol
  # SUZ12 was omitted by the model -> reconciled back as a pass-through keep.
  suz <- out[toupper(out$original) == "SUZ12", ]
  expect_equal(suz$action, "keep")
  expect_match(suz$reason, "pass-through")
})

test_that("build_input_prompt() grounds on the sources, types, and description", {
  cs <- candidate_set(
    candid_source(c("NF1", "TPP53"), label = "my degs", type = "rnaseq_deg")
  )
  p <- with_app_root(build_input_prompt(cs, "studying peripheral nerve tumors"))
  expect_match(p$system, "Never invent a gene", fixed = TRUE)
  expect_match(p$user, "my degs")
  expect_match(p$user, "rnaseq_deg")
  expect_match(p$user, "TPP53")
  expect_match(p$user, "peripheral nerve tumors")
})

test_that("fallback_input() passes every token through unchanged", {
  cs <- candidate_set(candid_source(c("NF1", "TP53"), label = "mine"))
  prop <- fallback_input(cs)
  expect_equal(nrow(prop$tokens), 2)
  expect_true(all(prop$tokens$action == "keep"))
  expect_setequal(prop$tokens$symbol, c("NF1", "TP53"))
  expect_equal(prop$proposed_disease$search_term, "") # no disease without the LLM
})

test_that("curate_input() applies the grounding gate with a stubbed model", {
  skip_if_not_installed("ellmer")
  factory <- function(system_prompt) {
    list(chat_structured = function(user, type) {
      list(
        tokens = list(
          list(
            original = "nf1",
            symbol = "NF1",
            action = "correct",
            reason = "alias",
            confidence = 0.9
          ),
          list(
            original = "TPP53",
            symbol = "TP53",
            action = "correct",
            reason = "typo",
            confidence = 0.95
          ),
          list(
            original = "GHOST",
            symbol = "MADEUP",
            action = "keep",
            reason = "x",
            confidence = 0.5
          )
        ),
        proposed_disease = list(
          name = "Neurofibromatosis type 1",
          search_term = "neurofibromatosis type 1"
        ),
        notes = "cleaned"
      )
    })
  }
  cs <- candidate_set(
    candid_source(c("nf1", "TPP53"), label = "degs", type = "rnaseq_deg")
  )
  prop <- with_app_root(curate_input(
    cs,
    description = "studying NF1",
    config = candid_config,
    chat_factory = factory,
    validator = function(symbols, species = "human") NULL # isolate from biogate
  ))
  expect_true(attr(prop, "ai_used"))
  # GHOST is not a provided token -> never appears; only the real tokens survive.
  expect_setequal(prop$tokens$original, c("nf1", "TPP53"))
  expect_equal(prop$tokens$symbol[prop$tokens$original == "nf1"], "NF1")
  expect_equal(prop$tokens$symbol[prop$tokens$original == "TPP53"], "TP53")
  expect_equal(prop$proposed_disease$search_term, "neurofibromatosis type 1")
})

test_that("curate_input() falls back (with the error) when the model throws", {
  prop <- with_app_root(curate_input(
    candidate_set(candid_source("NF1", label = "mine")),
    config = candid_config,
    chat_factory = function(system_prompt) stop("boom")
  ))
  expect_false(attr(prop, "ai_used"))
  expect_match(attr(prop, "error"), "boom")
  expect_equal(nrow(prop$tokens), 1)
})

test_that("confirm_input() groups kept symbols by source and excludes flag/drop", {
  cs <- candidate_set(
    candid_source(c("nf1", "junk"), label = "degs", type = "rnaseq_deg"),
    candid_source(c("TP53"), label = "atac", type = "atacseq")
  )
  decisions <- tibble::tibble(
    original = c("nf1", "junk", "TP53"),
    symbol = c("NF1", NA, "TP53"),
    action = c("correct", "drop", "keep"),
    reason = c("alias", "not a gene", "ok"),
    confidence = NA_real_
  )
  prop <- build_input_proposal(cs, decisions, empty_disease(), "n")
  confirmed <- confirm_input(prop)
  expect_s3_class(confirmed, "candid_candidate_set")

  degs <- Find(function(s) s$label == "degs", confirmed)
  atac <- Find(function(s) s$label == "atac", confirmed)
  expect_equal(degs$genes, "NF1") # junk (drop) excluded
  expect_equal(degs$type, "rnaseq_deg") # source type preserved
  expect_equal(atac$genes, "TP53")
})

test_that("confirm_input() honors user edits (add back and drop)", {
  cs <- candidate_set(
    candid_source(c("nf1", "junk"), label = "degs", type = "rnaseq_deg"),
    candid_source(c("TP53"), label = "atac", type = "atacseq")
  )
  decisions <- tibble::tibble(
    original = c("nf1", "junk", "TP53"),
    symbol = c("NF1", NA, "TP53"),
    action = c("correct", "drop", "keep"),
    reason = c("alias", "not a gene", "ok"),
    confidence = NA_real_
  )
  prop <- build_input_proposal(cs, decisions, empty_disease(), "n")
  edits <- tibble::tibble(
    source_id = c("degs", "atac"),
    original = c("junk", "TP53"),
    action = c("keep", "drop"),
    symbol = c("SUZ12", NA)
  )
  confirmed <- confirm_input(prop, edits)
  degs <- Find(function(s) s$label == "degs", confirmed)
  expect_setequal(degs$genes, c("NF1", "SUZ12")) # junk edited to a real gene
  expect_null(Find(function(s) s$label == "atac", confirmed)) # TP53 dropped -> empty
})

test_that("the biogate seam normalizes a retired symbol on the confirmed set", {
  skip_if_not_installed("ellmer")
  fake_validator <- function(symbols, species = "human") {
    tibble::tibble(
      input = symbols,
      valid = symbols != "MLL",
      normalized = ifelse(symbols == "MLL", "KMT2A", symbols),
      suggestion = ifelse(symbols == "MLL", "KMT2A", NA_character_)
    )
  }
  factory <- function(system_prompt) {
    list(chat_structured = function(user, type) {
      list(
        tokens = list(
          list(
            original = "MLL",
            symbol = "MLL",
            action = "keep",
            reason = "",
            confidence = 1
          ),
          list(
            original = "TP53",
            symbol = "TP53",
            action = "keep",
            reason = "",
            confidence = 1
          )
        ),
        proposed_disease = list(name = "", search_term = ""),
        notes = ""
      )
    })
  }
  cs <- candidate_set(candid_source(c("MLL", "TP53"), label = "mine"))
  prop <- with_app_root(curate_input(
    cs,
    config = candid_config,
    chat_factory = factory,
    validator = fake_validator
  ))
  confirmed <- confirm_input(prop)
  mine <- Find(function(s) s$label == "mine", confirmed)
  expect_setequal(mine$genes, c("KMT2A", "TP53")) # MLL -> KMT2A
})

test_that("default_input_validator() returns NULL when biogate is absent", {
  skip_if(requireNamespace("biogate", quietly = TRUE), "biogate is installed")
  expect_null(default_input_validator())
})

test_that("resolve_proposed_disease() short-circuits a blank term (no network)", {
  r <- resolve_proposed_disease("")
  expect_false(r$ok)
})

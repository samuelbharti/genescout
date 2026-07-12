# Agentic specialists - grounding gate, domain routing, and a stubbed-runner path
# (offline; no network, no ellmer required for the injected-runner path).

fake_spec_result <- function() {
  genes <- tibble::tibble(
    rank = 1:2,
    gene_id = c("ENSG1", "ENSG2"),
    symbol = c("NF1", "TP53"),
    composite = c(0.8, 0.5),
    grade = c("High", "Moderate")
  )
  evidence <- dplyr::bind_rows(
    evidence_long_rows(
      "ENSG1",
      "ot_assoc",
      "pathway-disease",
      "NF1-neurofibromatosis association",
      "score 0.90",
      0.9,
      "OT:ENSG1:MONDO",
      "https://x"
    ),
    evidence_long_rows(
      "ENSG1",
      "clinvar_path",
      "variant-effect",
      "3 pathogenic variants",
      "",
      3,
      "ClinVar:VCV1",
      "https://y"
    ),
    evidence_long_rows(
      "ENSG1",
      "pmc_hits",
      "literature",
      "NF1 review",
      "2020",
      NA,
      "PMID:111",
      "https://z"
    )
  )
  list(
    description = "NF1 study",
    genes = genes,
    evidence = evidence,
    context = list(
      disease = list(id = "MONDO:1", name = "neurofibromatosis type 1")
    )
  )
}

test_that("specialist_candidates() narrows to restrict_to, then takes top n by rank", {
  res <- fake_spec_result()
  # No restriction: the whole ranked set, in rank order.
  expect_equal(specialist_candidates(res, 10)$symbol, c("NF1", "TP53"))
  # Restrict to the curated shortlist (case-insensitive): only those genes.
  expect_equal(
    specialist_candidates(res, 10, restrict_to = c("tp53"))$symbol,
    "TP53"
  )
  # An empty restriction is treated as "no restriction", not "exclude everything".
  expect_equal(
    specialist_candidates(res, 10, restrict_to = character())$symbol,
    c("NF1", "TP53")
  )
})

# Cite a real id for the domain + a fabricated one, so grounding is exercised.
fake_runner <- function(system_prompt, user_prompts, schema) {
  real <- if (grepl("Variant", system_prompt)) {
    "ClinVar:VCV1"
  } else if (grepl("Pathway", system_prompt)) {
    "OT:ENSG1:MONDO"
  } else {
    "PMID:111"
  }
  lapply(user_prompts, function(p) {
    list(
      assessment = "Synthesis of the shown evidence.",
      findings = list(
        list(point = "grounded point", source_ids = list(real)),
        list(point = "hallucinated point", source_ids = list("FAKE:999"))
      ),
      strength = "strong",
      next_experiment = "Validate with an orthogonal assay."
    )
  })
}

test_that("specialist_evidence_ids filters by gene and domain", {
  ev <- fake_spec_result()$evidence
  expect_equal(specialist_evidence_ids(ev, "ENSG1", "literature"), "PMID:111")
  expect_setequal(
    specialist_evidence_ids(ev, "ENSG1", c("pathway-disease", "gene-disease")),
    "OT:ENSG1:MONDO"
  )
  expect_equal(specialist_evidence_ids(ev, "ENSG2", "literature"), character())
})

test_that("clean_specialist_result grounds ids and drops ungrounded findings", {
  raw <- list(
    assessment = "a",
    strength = "STRONG",
    findings = list(
      list(point = "p1", source_ids = list("PMID:1", "FAKE")),
      list(point = "p2", source_ids = list("NOPE")),
      list(point = "", source_ids = list("PMID:1"))
    )
  )
  out <- clean_specialist_result(raw, valid = c("PMID:1"))
  expect_equal(out$strength, "strong") # normalized to lowercase
  expect_equal(length(out$findings), 1) # p2 (ungrounded) + empty point dropped
  expect_equal(out$findings[[1]]$source_ids, "PMID:1") # FAKE dropped
})

test_that("coerce_parallel_rows unwraps a tibble's nested list-columns per row", {
  # Mimics parallel_chat_structured's shape: findings is a list-column whose i-th
  # element is that row's findings (a list of finding objects), not a wrapper.
  out <- tibble::tibble(
    assessment = c("a1", "a2"),
    strength = c("strong", "weak"),
    findings = list(
      list(list(point = "p", source_ids = list("X:1"))),
      list()
    ),
    next_experiment = c("e1", "e2")
  )
  rows <- coerce_parallel_rows(out)
  expect_length(rows, 2)
  expect_equal(rows[[1]]$assessment, "a1")
  # findings is the row's OWN list of findings, not a length-1 wrapper.
  expect_equal(rows[[1]]$findings[[1]]$point, "p")
  # a cleaned result over this coerced row grounds correctly end-to-end.
  cleaned <- clean_specialist_result(rows[[1]], valid = c("X:1"))
  expect_equal(cleaned$findings[[1]]$source_ids, "X:1")
})

test_that("coerce_parallel_rows passes a non-data-frame through unchanged", {
  lst <- list(list(assessment = "a"))
  expect_identical(coerce_parallel_rows(lst), lst)
})

test_that("clean_specialist_result coerces an unknown strength to moderate", {
  out <- clean_specialist_result(
    list(assessment = "a", strength = "amazing", findings = list()),
    valid = character()
  )
  expect_equal(out$strength, "moderate")
})

test_that("run_specialists routes evidence to the right specialists, grounded", {
  sp <- run_specialists(
    fake_spec_result(),
    config = candid_config,
    top_n = 10,
    runner = fake_runner
  )
  expect_true(sp$ai_used)
  nf1 <- sp$by_gene[["NF1"]]
  expect_setequal(
    names(nf1),
    c("variant-effect", "pathway-disease", "literature")
  )
  ve <- nf1[["variant-effect"]]
  expect_equal(length(ve$findings), 1) # the fabricated finding was dropped
  expect_equal(ve$findings[[1]]$source_ids, "ClinVar:VCV1")
  expect_equal(ve$strength, "strong")
  expect_match(ve$next_experiment, "orthogonal")
  expect_equal(nf1[["literature"]]$findings[[1]]$source_ids, "PMID:111")
  # TP53 has no evidence in any specialist domain -> never analyzed.
  expect_null(sp$by_gene[["TP53"]])
})

test_that("run_specialists never calls the runner for a gene without domain evidence", {
  called <- new.env()
  called$prompts <- 0L
  spy <- function(system_prompt, user_prompts, schema) {
    called$prompts <- called$prompts + length(user_prompts)
    fake_runner(system_prompt, user_prompts, schema)
  }
  run_specialists(fake_spec_result(), config = candid_config, runner = spy)
  # NF1 has evidence in all three domains (3 prompts); TP53 has none (0).
  expect_equal(called$prompts, 3L)
})

test_that("run_specialists returns ai_used = FALSE for an empty ranking", {
  empty <- list(
    genes = fake_spec_result()$genes[0, , drop = FALSE],
    evidence = empty_evidence_long(),
    context = list()
  )
  sp <- run_specialists(
    empty,
    config = candid_config,
    runner = function(...) stop("runner should not be called")
  )
  expect_false(sp$ai_used)
  expect_match(sp$message, "No ranked genes")
})

test_that("a runner error degrades gracefully (no findings, not a crash)", {
  sp <- run_specialists(
    fake_spec_result(),
    config = candid_config,
    runner = function(...) stop("boom")
  )
  expect_false(sp$ai_used)
  expect_match(sp$message, "boom")
  expect_length(sp$by_gene, 0)
})

# A synthesis runner citing a grounded id + a fabricated one (dropped by grounding).
fake_synth_runner <- function(system_prompt, user_prompts, schema) {
  lapply(user_prompts, function(p) {
    list(
      verdict = "Integrated read across the domains.",
      plausibility = "COMPELLING", # exercise case normalization
      caveats = list("one real caveat", ""), # blank dropped
      next_experiment = "Run the priority validation.",
      source_ids = list("ClinVar:VCV1", "FAKE:999") # FAKE dropped by grounding
    )
  })
}

test_that("gene_grounded_ids unions the specialists' grounded finding ids", {
  sp <- run_specialists(
    fake_spec_result(),
    config = candid_config,
    runner = fake_runner,
    synthesize = FALSE
  )
  expect_setequal(
    gene_grounded_ids(sp$by_gene[["NF1"]]),
    c("ClinVar:VCV1", "OT:ENSG1:MONDO", "PMID:111")
  )
})

test_that("clean_synthesis_result normalizes plausibility and grounds ids", {
  raw <- list(
    verdict = "v",
    plausibility = "banana",
    caveats = list("c1"),
    next_experiment = "n",
    source_ids = list("A", "B")
  )
  out <- clean_synthesis_result(raw, valid = c("A"))
  expect_equal(out$plausibility, "uncertain") # unknown -> uncertain
  expect_equal(out$source_ids, "A") # B dropped (not grounded)
  # An empty verdict yields NULL (nothing to show).
  expect_null(clean_synthesis_result(
    list(verdict = "", plausibility = "plausible"),
    valid = character()
  ))
})

test_that("run_synthesis attaches a grounded verdict per gene", {
  sp <- run_specialists(
    fake_spec_result(),
    config = candid_config,
    runner = fake_runner,
    synthesize = FALSE
  )
  by <- run_synthesis(sp$by_gene, context = list(), runner = fake_synth_runner)
  v <- by[["NF1"]]$verdict
  expect_equal(v$plausibility, "compelling") # normalized to lowercase
  expect_equal(v$source_ids, "ClinVar:VCV1") # grounded; FAKE dropped
  expect_setequal(v$caveats, "one real caveat") # blank dropped
  expect_match(v$next_experiment, "priority")
})

test_that("run_specialists chains synthesis when a synth_runner is given", {
  sp <- run_specialists(
    fake_spec_result(),
    config = candid_config,
    runner = fake_runner,
    synth_runner = fake_synth_runner
  )
  expect_true(sp$ai_used)
  v <- sp$by_gene[["NF1"]]$verdict
  expect_false(is.null(v))
  expect_equal(v$plausibility, "compelling")
  # The per-domain cards survive alongside the verdict.
  expect_true("variant-effect" %in% names(sp$by_gene[["NF1"]]))
})

test_that("run_specialists skips synthesis when only a specialist runner is injected", {
  # Offline safety: an injected specialist runner without a synth_runner must never
  # trigger a live synthesis call.
  sp <- run_specialists(
    fake_spec_result(),
    config = candid_config,
    runner = fake_runner
  )
  expect_null(sp$by_gene[["NF1"]]$verdict)
})

test_that("render_verdict renders the verdict, badge, and grounded ids or NULL", {
  v <- list(
    verdict = "Integrated read.",
    plausibility = "compelling",
    caveats = c("a caveat"),
    next_experiment = "Do X.",
    source_ids = c("ClinVar:VCV1")
  )
  html <- as.character(render_verdict(v))
  expect_match(html, "Verdict")
  expect_match(html, "compelling")
  expect_match(html, "ClinVar:VCV1", fixed = TRUE)
  expect_match(html, "Do X.", fixed = TRUE)
  expect_null(render_verdict(list(verdict = ""))) # empty verdict -> NULL
})

test_that("render_specialist_analysis renders grounded cards or NULL", {
  sp <- run_specialists(
    fake_spec_result(),
    config = candid_config,
    runner = fake_runner
  )
  gene_row <- fake_spec_result()$genes[1, , drop = FALSE] # NF1
  html <- as.character(render_specialist_analysis(gene_row, sp))
  expect_match(html, "Specialist analysis")
  expect_match(html, "ClinVar:VCV1", fixed = TRUE) # a grounded cited id shows
  expect_match(html, "orthogonal") # the next experiment shows
  expect_false(grepl("FAKE:999", html, fixed = TRUE)) # dropped id never rendered
  # A gene with no analysis renders nothing.
  tp53 <- fake_spec_result()$genes[2, , drop = FALSE]
  expect_null(render_specialist_analysis(tp53, sp))
})

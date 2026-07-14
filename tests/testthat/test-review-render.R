# Review-workbench renderers (the master-detail layout). Offline, no network:
# a stub result in, structural assertions on the emitted `.gs-*` markup out.

gs_fake_result <- function() {
  genes <- tibble::tibble(
    rank = c(1L, 2L, 3L),
    symbol = c("NF1", "CDKN2A", "TTN"),
    gene_id = c("ENSG00000196712", "ENSG00000147889", "ENSG00000155657"),
    resolved = c(TRUE, TRUE, TRUE),
    composite = c(0.86, 0.74, 0.71),
    grade = c("High", "High", "Vetoed"),
    vetoed = c(FALSE, FALSE, TRUE),
    caveats = list(
      character(),
      character(),
      "FLAGS / recurrent artifact gene."
    ),
    ot_assoc = c(0.95, 0.80, 0.30),
    ot_assoc_n = c(0.95, 0.80, 0.30),
    pmc_hits = c(1200, 340, 9800),
    pmc_hits_n = c(0.80, 0.55, 0.95),
    constraint = c(0.70, 0.90, NA_real_),
    constraint_n = c(0.70, 0.90, 0)
  )
  registry <- tibble::tibble(
    key = c("ot_assoc", "pmc_hits", "constraint"),
    label = c("Open Targets", "Literature", "Constraint (gnomAD)"),
    source = c("Open Targets", "Europe PMC", "gnomAD"),
    role = c("evidence", "evidence", "annotation"),
    weight = c(1.0, 0.5, 0.3),
    direction = c("higher_better", "higher_better", "higher_better")
  )
  evidence <- tibble::tibble(
    gene_id = c("ENSG00000196712", "ENSG00000155657"),
    domain = c("pathway-disease", "literature"),
    title = c(
      "Strong association with MPNST.",
      "Very high mention count (size artifact)."
    ),
    detail = c("association 0.95", "9800 mentions"),
    source_id = c("ENSG00000196712", "PMID:27149842"),
    source_url = c("", "https://europepmc.org/abstract/MED/27149842")
  )
  list(
    description = "NF1-associated MPNST",
    genes = genes,
    evidence = evidence,
    registry = registry,
    provenance = list(list(source = "MyGene"), list(source = "Open Targets")),
    context = list(
      disease = list(id = "MONDO:0018975", name = "NF1-associated MPNST")
    )
  )
}

render <- function(tag) htmltools::doRenderTags(tag)

test_that("gs_context_strip() shows the context pill, counts, and grade bar", {
  html <- render(gs_context_strip(gs_fake_result()))
  expect_match(html, "gs-strip")
  expect_match(html, "NF1-associated MPNST")
  expect_match(html, "gs-distbar")
  expect_match(html, "candidates ranked")
})

test_that("gs_ranked_table() carries row selection hooks and marks the veto row", {
  res <- gs_fake_result()
  html <- render(gs_ranked_table(
    res$genes,
    res$registry,
    verdicts = list(),
    selected = "NF1",
    input_id = "review-results-selected_symbol"
  ))
  expect_match(html, "gs-table")
  expect_match(html, 'data-symbol="NF1"', fixed = TRUE)
  expect_match(
    html,
    'data-input="review-results-selected_symbol"',
    fixed = TRUE
  )
  expect_match(html, "gs-grade veto") # TTN vetoed
  expect_match(html, 'class="[^"]*sel[^"]*"') # NF1 row is selected
  expect_false(grepl("Plausibility", html)) # no verdicts -> no column
})

test_that("gs_ranked_table() adds a Plausibility column when verdicts are present", {
  res <- gs_fake_result()
  verdicts <- list(NF1 = list(plausibility = "compelling"))
  html <- render(gs_ranked_table(
    res$genes,
    res$registry,
    verdicts = verdicts,
    selected = "NF1",
    input_id = "x-selected_symbol"
  ))
  expect_match(html, "Plausibility")
  expect_match(html, "gs-plaus compelling")
})

test_that("gs_detail_pane() renders breakdown, grounded evidence, and a verdict", {
  res <- gs_fake_result()
  verdict <- list(
    plausibility = "compelling",
    verdict = "Core driver of the disease.",
    next_experiment = "Confirm biallelic loss-of-function.",
    source_ids = c("PMID:35201422")
  )
  html <- render(gs_detail_pane(
    res$genes[1, , drop = FALSE],
    res$evidence,
    res$registry,
    verdict = verdict,
    spec_ran = TRUE
  ))
  expect_match(html, "Composite breakdown")
  expect_match(html, "gs-bd")
  expect_match(html, "Grounded evidence")
  expect_match(html, "Specialist verdict")
  expect_match(html, "Confirm biallelic loss-of-function")
  expect_match(html, "PMID:35201422")
})

test_that("gs_detail_pane() shows the veto note for a vetoed gene", {
  res <- gs_fake_result()
  html <- render(gs_detail_pane(
    res$genes[3, , drop = FALSE],
    res$evidence,
    res$registry,
    verdict = NULL,
    spec_ran = FALSE
  ))
  expect_match(html, "gs-veto-note")
  expect_match(html, "Vetoed")
  # No specialists run and not vetoed-only prompt: the empty verdict invites the run.
})

test_that("gs_detail_pane() invites a specialist run when none has happened", {
  res <- gs_fake_result()
  html <- render(gs_detail_pane(
    res$genes[1, , drop = FALSE],
    res$evidence,
    res$registry,
    verdict = NULL,
    spec_ran = FALSE
  ))
  expect_match(html, "Analyze with specialists")
})

test_that("gs_detail_pane() collapses evidence and slots the specialist analysis above it", {
  res <- gs_fake_result()
  sa <- tags$div(class = "specialist-card", "per-domain analysis here")
  html <- render(gs_detail_pane(
    res$genes[1, , drop = FALSE],
    res$evidence,
    res$registry,
    verdict = list(plausibility = "compelling", verdict = "Driver."),
    spec_ran = TRUE,
    specialist_analysis = sa
  ))
  expect_match(html, "<details") # grounded evidence collapsed by default
  expect_match(html, "Grounded evidence \\(") # count shown in the summary
  expect_match(html, "per-domain analysis here") # specialist analysis rendered
  # The verdict + specialist read comes before the (collapsed) evidence.
  expect_lt(
    regexpr("Verdict", html)[1],
    regexpr("Grounded evidence", html)[1]
  )
})

test_that("gs_ranked_table() renders an annotation signal with the secondary accent", {
  res <- gs_fake_result()
  html <- render(gs_ranked_table(res$genes, res$registry, input_id = "x"))
  # constraint is role = annotation -> a `teal` micro-bar class is emitted.
  expect_match(html, "gs-sig")
  expect_match(html, "teal")
})

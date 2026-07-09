# Report rendering over the gene x signal result shape (offline, no network).

fake_result <- function() {
  genes <- tibble::tibble(
    rank = c(1, 2),
    gene_id = c("ENSG00000196712", "UNRESOLVED:XYZ"),
    symbol = c("NF1", "XYZ"),
    resolved = c(TRUE, FALSE),
    input_lists = list("pasted", "pasted"),
    ot_assoc = c(0.72, NA_real_),
    ot_assoc_n = c(0.72, 0),
    pmc_hits = c(2530, NA_real_),
    pmc_hits_n = c(0.8, 0),
    clinvar_path = c(42, NA_real_),
    clinvar_path_n = c(0.9, 0),
    n_sources_present = c(3L, 0L),
    composite = c(0.7, 0),
    grade = c("High", "Insufficient")
  )
  evidence <- evidence_long_rows(
    "ENSG00000196712",
    "ot_assoc",
    "pathway-disease",
    "neurofibromatosis type 1",
    "association score 0.72",
    0.72,
    "OpenTargets:ENSG00000196712:MONDO_x",
    "https://x"
  )
  registry <- tibble::tibble(
    key = c("ot_assoc", "pmc_hits", "clinvar_path"),
    label = c(
      "Open Targets association",
      "Europe PMC mentions",
      "ClinVar pathogenic variants"
    ),
    source = c("Open Targets Platform", "Europe PMC", "ClinVar"),
    weight = c(1, 0.5, 1),
    role = c("evidence", "evidence", "evidence"),
    direction = c("higher_better", "higher_better", "higher_better")
  )
  list(
    description = "NF1-associated MPNST",
    genes = genes,
    evidence = evidence,
    registry = registry,
    provenance = list(list(source = "Open Targets Platform")),
    generated_with_llm = FALSE
  )
}

test_that("gene_matrix_display() builds a ranked table with per-signal columns", {
  disp <- gene_matrix_display(fake_result()$genes, fake_result()$registry)
  expect_equal(disp$Rank, c(1, 2))
  expect_equal(disp$Gene, c("NF1", "XYZ"))
  expect_true("Open Targets association" %in% names(disp))
  expect_equal(disp[["Open Targets association"]][1], "0.72")
  expect_equal(disp[["Europe PMC mentions"]][1], "2,530")
  expect_equal(disp[["Open Targets association"]][2], "—") # missing -> em dash
})

test_that("render_gene_evidence() shows grounded evidence with a source link", {
  res <- fake_result()
  html <- as.character(render_gene_evidence(
    res$genes[1, , drop = FALSE],
    res$evidence
  ))
  expect_match(html, "NF1")
  expect_match(html, "OpenTargets:ENSG00000196712")
})

test_that("render_gene_evidence() flags an unresolved gene", {
  res <- fake_result()
  html <- as.character(render_gene_evidence(
    res$genes[2, , drop = FALSE],
    res$evidence
  ))
  expect_match(html, "could not be resolved")
})

test_that("build_export_csv() flattens the ranked matrix with raw + norm cols", {
  df <- build_export_csv(fake_result())
  expect_equal(df$rank, c(1, 2))
  expect_equal(df$gene, c("NF1", "XYZ"))
  expect_true(all(
    c("ot_assoc", "ot_assoc_norm", "composite", "grade", "input_lists") %in%
      names(df)
  ))
  expect_equal(df$ot_assoc, c(0.72, NA))
  expect_equal(df$input_lists, c("pasted", "pasted"))
})

test_that("render_curation() labels AI rationales as non-citation-gated", {
  curated <- tibble::tibble(
    gene_symbol = "NF1",
    include = TRUE,
    confidence = 0.9,
    rationale = "Strong Open Targets association."
  )
  attr(curated, "ai_used") <- TRUE
  html <- as.character(render_curation(curated))
  expect_match(html, "AI-curated selection")
  expect_match(html, "not separately citation-gated", fixed = TRUE)
})

test_that("render_curation() omits the AI caveat for the fallback selection", {
  curated <- tibble::tibble(
    gene_symbol = "NF1",
    include = TRUE,
    confidence = NA_real_,
    rationale = "Selected by composite rank (AI unavailable)."
  )
  attr(curated, "ai_used") <- FALSE
  html <- as.character(render_curation(curated))
  expect_match(html, "Composite-rank selection")
  expect_false(grepl("not separately citation-gated", html, fixed = TRUE))
})

test_that("render_report() writes a self-contained HTML with the disclaimer", {
  out <- tempfile(fileext = ".html")
  on.exit(unlink(out), add = TRUE)
  render_report(fake_result(), out)

  expect_true(file.exists(out))
  html <- paste(readLines(out, warn = FALSE), collapse = "\n")
  expect_match(html, "Ranked genes")
  expect_match(html, "NF1")
  expect_match(html, "Research use only")
  expect_match(html, "Studying")
})

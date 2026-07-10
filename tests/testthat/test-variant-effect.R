# Variant-effect clients - offline parser + evidence-normalization tests.

test_that("ensembl_parse_vep() extracts the consequence summary and table", {
  res <- ensembl_parse_vep(read_fixture("ensembl_vep_rs113488022.json"))
  expect_true(res$ok)
  expect_equal(res$most_severe, "missense_variant")
  expect_s3_class(res$data, "data.frame")
  expect_named(
    res$data,
    c("gene", "transcript", "consequence", "impact", "sift", "polyphen")
  )
  expect_true(all(res$data$gene == "BRAF"))
})

test_that("ensembl_consequences_df() keeps only protein-coding rows", {
  coding <- list(
    list(
      biotype = "protein_coding",
      gene_symbol = "BRAF",
      transcript_id = "T1",
      consequence_terms = list("missense_variant"),
      impact = "MODERATE"
    ),
    list(
      biotype = "retained_intron",
      gene_symbol = "BRAF",
      transcript_id = "T2",
      consequence_terms = list("intron_variant"),
      impact = "MODIFIER"
    )
  )
  df <- ensembl_consequences_df(coding)
  expect_equal(nrow(df), 1)
  expect_equal(df$transcript, "T1")
  expect_null(ensembl_consequences_df(NULL))
})

test_that("clinvar_parse_record() extracts classification and conditions", {
  res <- clinvar_parse_record(read_fixture("clinvar_40389.json"), uid = "40389")
  expect_true(res$ok)
  expect_equal(res$significance, "Pathogenic")
  expect_match(res$review_status, "expert panel")
  expect_match(res$conditions, "RASopathy")
  expect_match(res$accession, "^VCV")
})

test_that("gnomad_freq_part() normalizes a frequency block and handles NULL", {
  variant <- read_fixture("gnomad_rs113488022.json")$data$variant
  part <- gnomad_freq_part(variant$exome)
  expect_equal(part$ac, 2)
  expect_true(part$af > 0)
  expect_null(gnomad_freq_part(NULL))
})

test_that("variant-effect evidence rows are grounded with source ids", {
  vep <- ensembl_parse_vep(read_fixture("ensembl_vep_rs113488022.json"))
  r1 <- vep_evidence("rs113488022", vep)
  expect_equal(r1$domain, "variant-effect")
  expect_match(r1$source_id, "^Ensembl:VEP:rs113488022")

  gf <- list(
    ok = TRUE,
    variant_id = "7-140753336-A-T",
    dataset = "gnomad_r4",
    exome = list(af = 1.37e-6, ac = 2, an = 1460618),
    genome = NULL
  )
  r2 <- gnomad_evidence(gf)
  expect_match(r2$source_id, "^gnomAD:7-140753336")

  cv <- clinvar_parse_record(read_fixture("clinvar_40389.json"), uid = "40389")
  r3 <- clinvar_evidence(cv)
  expect_match(r3$source_id, "^ClinVar:VCV")
})

# gnomAD gene-constraint (LOEUF) client - offline parser tests.

test_that("gnomad_constraint_parse() extracts LOEUF and pLI", {
  r <- gnomad_constraint_parse(read_fixture("gnomad_nf1.json"), "NF1")
  expect_true(r$ok)
  expect_equal(r$loeuf, 0.29)
  expect_equal(r$pli, 1.0)
  expect_match(r$source_id, "gnomAD:gene:NF1")
  expect_match(r$source_url, "/NF1")
})

test_that("gnomad_constraint_parse() is a miss when constraint is absent", {
  r <- gnomad_constraint_parse(read_fixture("gnomad_missing.json"), "XYZ")
  expect_false(r$ok)
})

test_that("gnomad_constraint_parse() is a miss when the gene is absent", {
  r <- gnomad_constraint_parse(list(data = list(gene = NULL)), "XYZ")
  expect_false(r$ok)
})

test_that("gnomad_loeuf() rejects a blank symbol", {
  expect_false(gnomad_loeuf("")$ok)
})

# --- gene-level max pLoF allele frequency (the "common variant" signal) --------

test_that("gnomad_lof_af_parse() takes the max pLoF AF, filtering out non-LoF", {
  r <- gnomad_lof_af_parse(read_fixture("gnomad_variants_gjb2.json"), "GJB2")
  expect_true(r$ok)
  # The common 35delG frameshift (AF 0.00713) dominates the pLoF set; a higher-AF
  # intron (0.069) and missense (0.026) in the same gene are correctly excluded.
  expect_equal(round(r$max_lof_af, 5), 0.00713)
  expect_equal(r$n_lof, 6)
  expect_match(r$source_id, "gnomAD:gene:GJB2:lof_af")
})

test_that("gnomad_lof_af_parse() is a REAL 0 when the gene has no pLoF variant", {
  data <- list(
    data = list(
      gene = list(
        variants = list(
          list(consequence = "missense_variant", exome = list(af = 0.2)),
          list(consequence = "intron_variant", genome = list(af = 0.3))
        )
      )
    )
  )
  r <- gnomad_lof_af_parse(data, "XYZ")
  expect_true(r$ok) # gene present -> ok, not a miss
  expect_equal(r$max_lof_af, 0) # no pLoF -> a real 0, so no spurious caveat
  expect_equal(r$n_lof, 0)
})

test_that("gnomad_lof_af_parse() is a miss when gene / variants are absent", {
  expect_false(gnomad_lof_af_parse(list(data = list(gene = NULL)), "XYZ")$ok)
  expect_false(gnomad_lof_af_parse(list(data = list(gene = list())), "XYZ")$ok)
})

test_that("gnomad_gene_max_lof_af() rejects a blank symbol", {
  expect_false(gnomad_gene_max_lof_af("")$ok)
})

# Bundled example inputs (offline).

test_that("genescout_multisource_example() returns four tagged assay sources", {
  ex <- genescout_multisource_example()
  expect_length(ex, 4)

  types <- vapply(ex, function(s) s$type, character(1))
  expect_true(all(c("wes", "rnaseq_deg", "atacseq", "crispr") %in% types))
  expect_true(all(types %in% genescout_source_types()))

  for (s in ex) {
    expect_true(nzchar(s$label))
    expect_gte(length(s$genes), 5)
    # plain gene symbols only (public identifiers, no free text)
    expect_true(all(grepl("^[A-Z0-9-]+$", s$genes)))
  }

  # Cross-source corroboration is the whole point: several genes recur across
  # lists (they should rank higher), and an artifact gene is present to exercise
  # the caveats/veto stage.
  all_genes <- unlist(lapply(ex, function(s) s$genes))
  recurring <- names(which(table(all_genes) >= 2))
  expect_gte(length(recurring), 3)
  expect_true("TTN" %in% all_genes)
})

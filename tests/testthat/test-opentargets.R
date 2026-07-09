# Phase 0 target: the Open Targets client is the first tool to implement end to
# end (fixture-backed parser test, then a live GraphQL call). Skipped until then
# so it marks the next milestone without falsely passing.

test_that("gene_disease_assoc() parses an Open Targets response", {
  skip(
    "Phase 0 target - implement R/tools/opentargets.R with an httptest2 fixture."
  )

  # Sketch of the intended offline test:
  #   res <- gene_disease_assoc("ENSG00000196712")  # NF1
  #   expect_s3_class(res, "data.frame")
  #   expect_true(all(c("disease", "score", "source_id") %in% names(res)))
  #   expect_true(all(nzchar(res$source_id)))
})

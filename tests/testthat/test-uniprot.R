# UniProt (Swiss-Prot) disease client - offline parser + context relevance. No network.

test_that("uniprot_disease_parse() distills curated disease involvement", {
  r <- uniprot_disease_parse(read_fixture("uniprot_disease_nf1.json"))
  expect_true(r$ok)
  expect_true(all(
    c("id", "name", "acronym", "mim", "causal", "source_id") %in%
      names(r$diseases)
  ))
  # Neurofibromatosis 1 is present, grounded by its UniProt disease id + MIM xref.
  nf1 <- r$diseases[r$diseases$name == "Neurofibromatosis 1", ]
  expect_equal(nrow(nf1), 1)
  expect_equal(nf1$id, "DI-02396")
  expect_equal(nf1$mim, "162200")
  expect_equal(nf1$source_id, "UniProt:DI-02396")
  expect_match(nf1$source_url, "uniprot.org/diseases/DI-02396", fixed = TRUE)
  # The note "caused by variants" marks a causal (Mendelian) link; colorectal
  # cancer's "may be involved in pathogenesis" note does not.
  expect_true(nf1$causal)
  crc <- r$diseases[r$diseases$name == "Colorectal cancer", ]
  expect_false(crc$causal)
})

test_that("uniprot_disease_parse() reports a miss when there is no DISEASE comment", {
  expect_false(uniprot_disease_parse(list(comments = list()))$ok)
  expect_false(uniprot_disease_parse(list())$ok)
  # A non-disease comment is ignored, so an entry with only those is still a miss.
  only_other <- list(comments = list(list(commentType = "FUNCTION")))
  expect_false(uniprot_disease_parse(only_other)$ok)
})

test_that("uniprot_disease_relevance() counts all diseases with no context", {
  r <- uniprot_disease_parse(read_fixture("uniprot_disease_nf1.json"))
  rel <- uniprot_disease_relevance(r$diseases, disease_ctx = NULL)
  expect_true(rel$present)
  expect_equal(rel$n, nrow(r$diseases))
})

test_that("uniprot_disease_relevance() scopes to the disease context by name", {
  r <- uniprot_disease_parse(read_fixture("uniprot_disease_nf1.json"))
  rel <- uniprot_disease_relevance(
    r$diseases,
    disease_ctx = list(name = "neurofibromatosis type 1")
  )
  expect_true(rel$present)
  # Matches the neurofibromatosis-named entries (NF1, familial spinal
  # neurofibromatosis, neurofibromatosis-Noonan) on the specific token, not the
  # generic "syndrome"/"cancer" ones.
  expect_true(all(grepl("neurofibromatosis", tolower(rel$matched$name))))
  # An unrelated context matches nothing -> not present.
  rel2 <- uniprot_disease_relevance(
    r$diseases,
    disease_ctx = list(name = "cystic fibrosis")
  )
  expect_false(rel2$present)
})

test_that("uniprot_gene_diseases() rejects a blank / non-accession id", {
  expect_false(uniprot_gene_diseases("")$ok)
  expect_false(uniprot_gene_diseases("!!!")$ok)
})

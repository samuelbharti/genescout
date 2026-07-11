# PDBe structure client - offline parser + de-duplication by PDB id. No network.

test_that("pdbe_structures_parse() counts distinct experimental structures", {
  r <- pdbe_structures_parse(read_fixture("pdbe_nf1.json"), "P21359")
  expect_true(r$ok)
  # The mapping lists one row per chain; the parser collapses to distinct PDB ids.
  expect_false(any(duplicated(r$structures$pdb_id)))
  expect_equal(r$n, nrow(r$structures))
  expect_true("1nf1" %in% r$structures$pdb_id) # the classic NF1 GRD crystal
  row <- r$structures[r$structures$pdb_id == "1nf1", ]
  expect_equal(row$source_id, "PDB:1nf1")
  expect_match(row$source_url, "pdbe/entry/pdb/1nf1", fixed = TRUE)
})

test_that("pdbe_structures_parse() falls back to the first value when unkeyed", {
  # Same body, but looked up without knowing the accession key: the parser takes
  # the first (only) value rather than returning a miss.
  body <- read_fixture("pdbe_nf1.json")
  r <- pdbe_structures_parse(body, "WRONGKEY")
  expect_true(r$ok)
  expect_true(r$n > 0)
})

test_that("pdbe_structures_parse() reports a miss when there are no structures", {
  expect_false(pdbe_structures_parse(list(), "P0")$ok)
  expect_false(pdbe_structures_parse(list(P0 = list()), "P0")$ok)
})

test_that("pdbe_structures() rejects a blank / non-accession id", {
  expect_false(pdbe_structures("")$ok)
  expect_false(pdbe_structures("!!!")$ok)
})

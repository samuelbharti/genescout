# DISEASES (Jensen Lab) disease-gene client - offline parser tests.

test_that("diseases_channel_parse() extracts genes + scores from a channel body", {
  genes <- diseases_channel_parse(read_fixture("diseases_nf1.json"))
  expect_true(all(c("symbol", "score") %in% names(genes)))
  expect_equal(nrow(genes), 4)
  expect_true(all(c("NF1", "SUZ12", "CDKN2A", "TP53") %in% genes$symbol))
  expect_equal(genes$score[genes$symbol == "NF1"], 5.0)
  expect_equal(genes$score[genes$symbol == "CDKN2A"], 3.5)
})

test_that("diseases_channel_parse() returns an empty tibble for no data", {
  expect_equal(nrow(diseases_channel_parse(list())), 0)
  expect_equal(nrow(diseases_channel_parse(list(list()))), 0)
  expect_equal(nrow(diseases_channel_parse(NULL)), 0)
})

test_that("diseases_merge() keeps the per-gene MAX score across channels", {
  knowledge <- tibble::tibble(
    symbol = c("NF1", "SUZ12"),
    score = c(4.0, 3.0)
  )
  textmining <- tibble::tibble(
    symbol = c("NF1", "CDKN2A"),
    score = c(5.0, 2.0)
  )
  merged <- diseases_merge(list(knowledge, textmining))

  expect_equal(nrow(merged), 3)
  expect_true(all(c("NF1", "SUZ12", "CDKN2A") %in% merged$symbol))
  # NF1 appears in both channels; the stronger (5.0) wins.
  expect_equal(merged$score[merged$symbol == "NF1"], 5.0)
  expect_equal(merged$score[merged$symbol == "SUZ12"], 3.0)
  # Ordered by score, highest first.
  expect_equal(merged$symbol[1], "NF1")
})

test_that("diseases_merge() ignores NULL and empty channels", {
  only <- tibble::tibble(symbol = "NF1", score = 5.0)
  empty <- tibble::tibble(symbol = character(), score = numeric())
  merged <- diseases_merge(list(only, empty, NULL))
  expect_equal(nrow(merged), 1)
  expect_equal(merged$symbol, "NF1")

  expect_equal(nrow(diseases_merge(list(NULL, empty))), 0)
})

test_that("diseases_gene_associations() rejects a blank DOID", {
  expect_false(diseases_gene_associations("")$ok)
  expect_false(diseases_gene_associations(NA)$ok)
  expect_false(diseases_gene_associations(NULL)$ok)
})

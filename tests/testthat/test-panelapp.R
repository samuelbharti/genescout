# Genomics England PanelApp client - offline parser + token-matching tests. The
# fetch/parse split keeps these network-free.

test_that("panelapp_panel_parse keeps green + amber and drops red", {
  genes <- panelapp_panel_parse(read_fixture("panelapp_panel.json"))

  expect_s3_class(genes, "data.frame")
  expect_true(all(c("symbol", "confidence") %in% names(genes)))
  # Green (NF1, SUZ12) + amber (SPRED1) kept; red (LZTR1) dropped.
  expect_setequal(genes$symbol, c("NF1", "SUZ12", "SPRED1"))
  expect_false("LZTR1" %in% genes$symbol)
  expect_equal(genes$confidence[genes$symbol == "NF1"], 1.0)
  expect_equal(genes$confidence[genes$symbol == "SUZ12"], 1.0)
  expect_equal(genes$confidence[genes$symbol == "SPRED1"], 0.5)
})

test_that("panelapp_panel_parse returns an empty typed tibble for no genes", {
  empty <- panelapp_panel_parse(list())
  expect_equal(nrow(empty), 0)
  expect_true(all(c("symbol", "confidence") %in% names(empty)))
  expect_true(is.numeric(empty$confidence))
})

test_that("panelapp_tokens drops short and generic words", {
  toks <- panelapp_tokens("Inherited breast and ovarian cancer syndrome")
  expect_true(all(c("breast", "ovarian", "cancer") %in% toks))
  expect_false("syndrome" %in% toks) # stop word
  expect_false("inherited" %in% toks) # stop word
  expect_false("and" %in% toks) # too short + stop word
  expect_equal(panelapp_tokens(""), character())
})

test_that("panelapp_pick_panel needs a strict majority of disease tokens", {
  panels <- list(
    list(
      id = 1,
      name = "Inherited breast and ovarian cancer",
      relevant_disorders = list("Breast cancer", "Ovarian cancer")
    ),
    list(
      id = 2,
      name = "Generic cancer predisposition",
      relevant_disorders = list()
    )
  )

  pick <- panelapp_pick_panel(panels, "Familial breast ovarian cancer")
  expect_equal(pick$id, 1)
  expect_equal(pick$name, "Inherited breast and ovarian cancer")
})

test_that("panelapp_pick_panel returns NULL on only a single broad-token match", {
  # Shares only "cancer" with the disease -> below the strict-majority threshold.
  panels <- list(
    list(
      id = 5,
      name = "Generic cancer predisposition",
      relevant_disorders = list()
    )
  )
  expect_null(panelapp_pick_panel(panels, "Familial breast ovarian cancer"))
})

test_that("panelapp_pick_panel accepts a raw index page with a results field", {
  page <- list(
    results = list(
      list(
        id = 255,
        name = "Neurofibromatosis Type 1",
        relevant_disorders = list("NF1")
      )
    ),
    `next` = NULL
  )
  pick <- panelapp_pick_panel(page, "Neurofibromatosis")
  expect_equal(pick$id, 255)
})

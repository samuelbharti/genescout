# Connectors reference page - the catalog display builder + render. Offline; the
# page is built from candid_source_catalog() metadata, no network.

rubric_path <- function() test_path("..", "..", "rubric.yml")
test_catalog <- function() candid_source_catalog(load_rubric(rubric_path()))

test_that("candid_connector_rows() has one row per catalog source, all fields set", {
  cat <- test_catalog()
  rows <- candid_connector_rows(cat)
  expect_equal(nrow(rows), length(cat)) # never silently drops a connector
  expect_setequal(rows$key, vapply(cat, function(s) s$key, character(1)))
  expect_true(all(nzchar(rows$label)))
  expect_true(all(nzchar(rows$source)))
  expect_true(all(nzchar(rows$status)))
  # Every domain is either a known report-domain key or the "other" bucket.
  expect_true(all(rows$domain %in% c(names(CANDID_DOMAIN_LABELS), "other")))
})

test_that("candid_connector_rows() describes the newly added connectors", {
  rows <- candid_connector_rows(test_catalog())
  for (k in c("go", "uniprot_disease", "pdbe", "impc")) {
    r <- rows[rows$key == k, ]
    expect_equal(nrow(r), 1)
    expect_true(nzchar(r$description)) # this batch ships with a blurb
  }
  expect_equal(rows$domain[rows$key == "go"], "function")
  expect_equal(rows$domain[rows$key == "pdbe"], "structure")
  expect_equal(rows$domain[rows$key == "uniprot_disease"], "gene-disease")
  expect_equal(rows$domain[rows$key == "impc"], "model-organism")
})

test_that("connector_status() derives the selection status from catalog metadata", {
  keyless_default <- candid_signal("k", "K", "S", NULL, normalize_identity)
  expect_equal(connector_status(keyless_default)$label, "Default on")

  opt_in <- candid_signal(
    "o",
    "O",
    "S",
    NULL,
    normalize_identity,
    default_on = FALSE
  )
  expect_equal(connector_status(opt_in)$label, "Opt-in")

  auto <- candid_signal(
    "c",
    "C",
    "S",
    NULL,
    normalize_identity,
    needs = "input"
  )
  expect_equal(connector_status(auto)$label, "Automatic")

  gtex <- candid_signal("gtex_tissue", "G", "GTEx", NULL, normalize_identity)
  expect_equal(connector_status(gtex)$label, "Contextual")

  stub <- candid_signal(
    "s",
    "S",
    "S",
    NULL,
    normalize_identity,
    stub = TRUE,
    auth = "bearer",
    key_env = "CANDID_ABSENT"
  )
  expect_equal(connector_status(stub)$label, "Planned")

  gated <- candid_signal(
    "g",
    "G",
    "S",
    NULL,
    normalize_identity,
    auth = "bearer",
    key_env = "CANDID_ABSENT_KEY_XYZ"
  )
  withr::with_envvar(c(CANDID_ABSENT_KEY_XYZ = ""), {
    expect_equal(connector_status(gated)$label, "Needs a key")
  })
})

test_that("candid_connector_summary() counts add up to the catalog size", {
  rows <- candid_connector_rows(test_catalog())
  sm <- candid_connector_summary(rows)
  expect_equal(sm$total, nrow(rows))
  expect_true(sm$domains >= 6)
  expect_true(sm$default_on > 0)
  expect_true(sm$opt_in > 0) # the opt-in connectors (hpo, go, pdbe, ...)
})

test_that("render_connectors_page() builds HTML with sources, domains, and disclaimer", {
  html <- as.character(render_connectors_page(test_catalog()))
  expect_match(html, "Connectors")
  expect_match(html, "Open Targets association", fixed = TRUE)
  expect_match(html, "Gene Ontology function", fixed = TRUE) # a new connector
  expect_match(html, "Molecular function (GO)", fixed = TRUE) # its domain label
  expect_match(html, "Research use only", fixed = TRUE)
  # A homepage link is rendered for a source that has one.
  expect_match(html, "platform.opentargets.org", fixed = TRUE)
})

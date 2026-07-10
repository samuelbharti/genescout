# Source catalog + per-run selection. The core promise: a DESELECTED source is
# never queried (unlike a weight of 0, which still pays the network cost). Offline.

rubric_path <- function() test_path("..", "..", "rubric.yml")

test_that("candid_source_catalog() lists every known source, incl. gtex + string", {
  cat <- candid_source_catalog(load_rubric(rubric_path()))
  keys <- vapply(cat, function(s) s$key, character(1))
  expect_true(all(
    c(
      "ot_assoc",
      "pmc_hits",
      "pubtator",
      "clinvar_path",
      "dgidb",
      "gnomad_loeuf",
      "pharos_tdl",
      "reactome",
      "panelapp",
      "diseases",
      "cross_source",
      "gtex_tissue",
      "string"
    ) %in%
      keys
  ))
  # Every catalog entry carries the selection metadata.
  expect_true(all(vapply(
    cat,
    function(s) "default_on" %in% names(s),
    logical(1)
  )))
})

test_that("source_selection() precedence: explicit > config > NULL(default_on)", {
  expect_equal(source_selection(c("a", "b"), list(sources = "z")), c("a", "b"))
  expect_equal(source_selection(NULL, list(sources = c("z"))), "z")
  expect_null(source_selection(NULL, NULL))
  expect_null(source_selection(NULL, list())) # config without a sources field
})

test_that("resolve_active_sources() honors selection, config, and default_on", {
  cat <- list(
    candid_signal("a", "A", "S", NULL, normalize_identity, default_on = TRUE),
    candid_signal("b", "B", "S", NULL, normalize_identity, default_on = FALSE)
  )
  # No selection -> only default_on.
  expect_equal(resolve_active_sources(cat), "a")
  # Explicit selection wins (even over a default-off source).
  expect_setequal(
    resolve_active_sources(cat, selection = c("a", "b")),
    c("a", "b")
  )
  # Config default used when no explicit selection.
  expect_equal(resolve_active_sources(cat, config = list(sources = "b")), "b")
  # Unknown keys are ignored.
  expect_equal(resolve_active_sources(cat, selection = c("a", "nope")), "a")
})

test_that("signal_available() drops a key-gated source with no key", {
  keyless <- candid_signal("k", "K", "S", NULL, normalize_identity)
  gated <- candid_signal(
    "g",
    "G",
    "S",
    NULL,
    normalize_identity,
    auth = "header",
    key_env = "CANDID_TEST_ABSENT_KEY"
  )
  expect_true(signal_available(keyless))
  withr::with_envvar(c(CANDID_TEST_ABSENT_KEY = ""), {
    expect_false(signal_available(gated))
    expect_false("g" %in% resolve_active_sources(list(keyless, gated)))
  })
  withr::with_envvar(c(CANDID_TEST_ABSENT_KEY = "xyz"), {
    expect_true(signal_available(gated))
  })
})

# A spy extractor that records how many times it is called.
spy_signal <- function(key, calls) {
  force(key)
  force(calls)
  extractor <- function(resolved, context = list()) {
    calls[[key]] <- (calls[[key]] %||% 0L) + 1L
    list(
      ok = TRUE,
      raw = 1,
      source_id = paste0("SPY:", key),
      source_url = "",
      evidence = empty_evidence_long()
    )
  }
  candid_signal(key, toupper(key), "Spy", extractor, normalize_identity, 1)
}

test_that("run_enrich() QUERIES only selected sources (deselected never called)", {
  calls <- new.env(parent = emptyenv())
  reg <- list(spy_signal("a", calls), spy_signal("b", calls))
  run_enrich(
    list(mine = c("NF1", "TP53")),
    registry = reg,
    resolver = stub_resolver,
    enabled = c("a") # select only 'a'
  )
  expect_true((calls$a %||% 0L) > 0L) # selected -> queried
  expect_null(calls$b) # deselected -> its extractor was never called
})

test_that("run_enrich() default selection (NULL) queries every default_on source", {
  calls <- new.env(parent = emptyenv())
  reg <- list(spy_signal("a", calls), spy_signal("b", calls))
  run_enrich(
    list(mine = c("NF1", "TP53")),
    registry = reg,
    resolver = stub_resolver
  )
  expect_true((calls$a %||% 0L) > 0L)
  expect_true((calls$b %||% 0L) > 0L)
})

test_that("run_enrich() errors when the selection leaves no sources", {
  reg <- list(spy_signal("a", new.env(parent = emptyenv())))
  expect_error(
    run_enrich(
      list(mine = "NF1"),
      registry = reg,
      resolver = stub_resolver,
      enabled = c("nonexistent")
    ),
    "No data sources selected"
  )
})

test_that("run_review_request() reads options$sources as the selection", {
  calls <- new.env(parent = emptyenv())
  reg <- list(spy_signal("a", calls), spy_signal("b", calls))
  req <- list(
    sources = candidate_set(candid_source(c("NF1", "TP53"), label = "mine")),
    options = list(sources = c("b"), caveats = FALSE)
  )
  run_review_request(req, registry = reg, resolver = stub_resolver)
  expect_null(calls$a) # 'a' not selected -> never queried
  expect_true((calls$b %||% 0L) > 0L)
})

test_that("candid_source_stubs() are catalog-visible but off + unavailable keyless", {
  cat <- candid_source_catalog(load_rubric(rubric_path()))
  keys <- vapply(cat, function(s) s$key, character(1))
  # The key-gated stubs appear in the catalog (so a front end can show 'needs key')...
  expect_true(all(
    c("oncokb", "cosmic_cgc", "disgenet", "omim", "drugbank") %in% keys
  ))
  stubs <- Filter(function(s) s$key %in% c("oncokb", "omim"), cat)
  # ...are opt-in (default_on FALSE) and every one declares an auth method + key env.
  expect_true(all(vapply(stubs, function(s) !isTRUE(s$default_on), logical(1))))
  expect_true(all(vapply(stubs, function(s) !is.null(s$key_env), logical(1))))
  # Without their keys they are unavailable, so the default selection excludes them.
  withr::with_envvar(
    c(ONCOKB_API_KEY = "", OMIM_API_KEY = ""),
    expect_false(any(c("oncokb", "omim") %in% resolve_active_sources(cat)))
  )
})

test_that("source_auth_headers() builds bearer headers only when a key is present", {
  keyless <- candid_signal("k", "K", "S", NULL, normalize_identity)
  expect_null(source_auth_headers(keyless))
  gated <- candid_signal(
    "g",
    "G",
    "S",
    NULL,
    normalize_identity,
    auth = "bearer",
    key_env = "CANDID_TEST_TOKEN"
  )
  withr::with_envvar(c(CANDID_TEST_TOKEN = ""), {
    expect_null(source_auth_headers(gated)) # no key -> no headers
  })
  withr::with_envvar(c(CANDID_TEST_TOKEN = "tok123"), {
    h <- source_auth_headers(gated)
    expect_equal(h$Authorization, "Bearer tok123")
  })
})

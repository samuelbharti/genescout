# Source catalog + per-run selection. The core promise: a DESELECTED source is
# never queried (unlike a weight of 0, which still pays the network cost). Offline.

rubric_path <- function() test_path("..", "..", "rubric.yml")

test_that("genescout_source_catalog() lists every known source, incl. gtex + string", {
  cat <- genescout_source_catalog(load_rubric(rubric_path()))
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
    genescout_signal(
      "a",
      "A",
      "S",
      NULL,
      normalize_identity,
      default_on = TRUE
    ),
    genescout_signal(
      "b",
      "B",
      "S",
      NULL,
      normalize_identity,
      default_on = FALSE
    )
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
  keyless <- genescout_signal("k", "K", "S", NULL, normalize_identity)
  gated <- genescout_signal(
    "g",
    "G",
    "S",
    NULL,
    normalize_identity,
    auth = "header",
    key_env = "GENESCOUT_TEST_ABSENT_KEY"
  )
  expect_true(signal_available(keyless))
  withr::with_envvar(c(GENESCOUT_TEST_ABSENT_KEY = ""), {
    expect_false(signal_available(gated))
    expect_false("g" %in% resolve_active_sources(list(keyless, gated)))
  })
  withr::with_envvar(c(GENESCOUT_TEST_ABSENT_KEY = "xyz"), {
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
  genescout_signal(key, toupper(key), "Spy", extractor, normalize_identity, 1)
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
    sources = candidate_set(genescout_source(c("NF1", "TP53"), label = "mine")),
    options = list(sources = c("b"), caveats = FALSE)
  )
  run_review_request(req, registry = reg, resolver = stub_resolver)
  expect_null(calls$a) # 'a' not selected -> never queried
  expect_true((calls$b %||% 0L) > 0L)
})

test_that("genescout_source_stubs() are catalog-visible but off + unavailable keyless", {
  cat <- genescout_source_catalog(load_rubric(rubric_path()))
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

test_that("genescout_catalog_json() is plain, JSON-serializable data with metadata", {
  j <- genescout_catalog_json(genescout_source_catalog(load_rubric(rubric_path())))
  expect_gt(length(j), 8)
  one <- j[[1]]
  expect_true(all(
    c(
      "key",
      "label",
      "source",
      "domain",
      "role",
      "default_on",
      "auth",
      "available"
    ) %in%
      names(one)
  ))
  # No closures survive - every field is an atomic scalar, so jsonlite serializes it.
  expect_silent(jsonlite::toJSON(j, auto_unbox = TRUE))
  keys <- vapply(j, function(s) s$key, character(1))
  hpa <- j[[which(keys == "hpa")]]
  expect_equal(hpa$domain, "cancer")
  expect_false(hpa$default_on) # opt-in
  # A key-gated stub is unavailable without its key.
  withr::with_envvar(c(ONCOKB_API_KEY = ""), {
    oncokb <- genescout_catalog_json(genescout_source_catalog(load_rubric(rubric_path())))
    ok <- oncokb[[which(
      vapply(oncokb, function(s) s$key, character(1)) == "oncokb"
    )]]
    expect_false(ok$available)
    expect_equal(ok$auth, "bearer")
  })
})

test_that("source_auth_headers() builds bearer headers only when a key is present", {
  keyless <- genescout_signal("k", "K", "S", NULL, normalize_identity)
  expect_null(source_auth_headers(keyless))
  gated <- genescout_signal(
    "g",
    "G",
    "S",
    NULL,
    normalize_identity,
    auth = "bearer",
    key_env = "GENESCOUT_TEST_TOKEN"
  )
  withr::with_envvar(c(GENESCOUT_TEST_TOKEN = ""), {
    expect_null(source_auth_headers(gated)) # no key -> no headers
  })
  withr::with_envvar(c(GENESCOUT_TEST_TOKEN = "tok123"), {
    h <- source_auth_headers(gated)
    expect_equal(h$Authorization, "Bearer tok123")
  })
})

# A stubbed STRING fetch so the >= 5-gene runs below stay offline.
fake_string_fetch <- function(symbols, ...) {
  list(
    ok = TRUE,
    edges = string_network_parse(read_fixture("string_network.json")),
    queried = symbols,
    source_url = "https://string-db.org/x"
  )
}

test_that("a non-null gene-only selection still appends cross_source + STRING", {
  # Regression (critical): the Shiny picker sends a non-null vector of GENE-source
  # keys and can never include the runtime auto-signals (cross_source needs="input",
  # string needs="network"). Those must still append, so a UI run matches the
  # CLI/eval default (non-negotiables #3, #5) instead of silently dropping them.
  reg <- stub_registry()
  gene_keys <- vapply(reg, function(s) s$key, character(1))
  enr <- run_enrich(
    list(a = c("NF1", "SUZ12", "CDKN2A"), b = c("NF1", "TP53", "EED")),
    registry = reg,
    resolver = stub_resolver,
    fetch_network = fake_string_fetch,
    enabled = gene_keys # exactly what the picker sends by default
  )
  expect_true("cross_source" %in% enr$registry$key) # >= 2 user sources
  expect_true("string" %in% enr$registry$key) # >= 5 genes
  # Byte-for-byte with the default (enabled = NULL) run.
  base <- run_enrich(
    list(a = c("NF1", "SUZ12", "CDKN2A"), b = c("NF1", "TP53", "EED")),
    registry = stub_registry(),
    resolver = stub_resolver,
    fetch_network = fake_string_fetch
  )
  expect_setequal(enr$registry$key, base$registry$key)
})

test_that("an explicit empty selection (deselect-all) queries nothing and errors", {
  # Regression (high): a UI deselect-all arrives as character(0), which must error
  # rather than silently fall back to the full default set. The STRING fetch must
  # never fire (the error is raised before any append/enrichment).
  expect_error(
    run_enrich(
      list(mine = c("NF1", "TP53", "AAA", "BBB", "CCC")),
      registry = stub_registry(),
      resolver = stub_resolver,
      fetch_network = function(...) stop("must not query"),
      enabled = character(0)
    ),
    "No data sources selected"
  )
})

test_that("genescout_provenance() audits GTEx only when gtex_tissue actually ran", {
  # Regression: tissues set but GTEx deselected -> not queried -> must not appear.
  off <- genescout_provenance(list(
    tissues_of_interest = "nerve",
    active_sources = c("ot_assoc")
  ))
  expect_false(any(grepl(
    "GTEx",
    vapply(off, function(s) s$source, character(1))
  )))
  on <- genescout_provenance(list(
    tissues_of_interest = "nerve",
    active_sources = c("ot_assoc", "gtex_tissue")
  ))
  expect_true(any(grepl(
    "GTEx",
    vapply(on, function(s) s$source, character(1))
  )))
})

test_that("genescout_provenance() audits disease seeding even if those signals are off", {
  # Regression: in discovery mode the seeder always queries Open Targets, PanelApp
  # and DISEASES, so the audit must list them even when their per-gene signal was
  # deselected (else provenance under-reports what actually ran).
  prov <- genescout_provenance(list(
    disease = list(id = "MONDO_0018975", name = "neurofibromatosis type 1"),
    active_sources = c("gnomad_loeuf") # none of the three seeders selected
  ))
  labs <- vapply(prov, function(s) s$source, character(1))
  expect_true(any(grepl("Open Targets", labs)))
  expect_true(any(grepl("PanelApp", labs)))
  expect_true(any(grepl("DISEASES", labs)))
})

test_that("genescout_provenance() audits the cancer connectors when they ran", {
  # A selected opt-in connector that produced evidence must appear in the audit
  # trail (the base provenance list has to know its endpoint).
  prov <- genescout_provenance(list(
    active_sources = c("ot_assoc", "cbioportal", "civic", "clingen")
  ))
  labs <- vapply(prov, function(s) s$source, character(1))
  expect_true(any(grepl("cBioPortal", labs)))
  expect_true(any(grepl("CIViC", labs)))
  expect_true(any(grepl("ClinGen", labs)))
})

test_that("genescout_catalog_json() flags catalog-only stubs as not selectable", {
  j <- genescout_catalog_json(genescout_source_catalog(load_rubric(rubric_path())))
  by_key <- function(k) {
    j[[which(vapply(j, function(s) s$key, character(1)) == k)]]
  }
  expect_true(by_key("oncokb")$stub) # key-gated stub, no live client yet
  expect_false(by_key("ot_assoc")$stub) # a real, runnable source
  expect_false(by_key("hpo")$stub) # opt-in but runnable
})

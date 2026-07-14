# Discovery (disease-mode) seeding + disease-aware extractors, offline.

test_that("seed_row() looks up a symbol in a stashed seed table", {
  ctx <- list(
    seed_data = list(
      panelapp = tibble::tibble(
        symbol = c("NF1", "TP53"),
        raw = c(1.0, 0.5),
        source_id = c("a", "b"),
        source_url = c("u", "v")
      )
    )
  )
  hit <- seed_row(ctx, "panelapp", "nf1") # case-insensitive
  expect_equal(hit$raw, 1.0)
  expect_null(seed_row(ctx, "panelapp", "XYZ"))
  expect_null(seed_row(list(), "panelapp", "NF1"))
})

test_that("seed_row() matches any of several aliases for one gene", {
  # The seed table is keyed by the SOURCE symbol (e.g. STRING's "MLL"); MyGene may
  # canonicalize the token to a different symbol ("KMT2A"). seed_row must still hit
  # when handed both the canonical and the original symbol.
  ctx <- list(
    seed_data = list(
      diseases = tibble::tibble(
        symbol = "MLL",
        raw = 4.0,
        source_id = "d",
        source_url = "v"
      )
    )
  )
  hit <- seed_row(ctx, "diseases", c("KMT2A", "MLL"))
  expect_equal(hit$raw, 4.0)
  # only the canonical symbol -> the aliased seed is missed
  expect_null(seed_row(ctx, "diseases", "KMT2A"))
})

test_that("extract_diseases() finds a seed keyed under an alias via input_symbols", {
  ctx <- list(
    disease = list(id = "X", name = "X"),
    seed_data = list(
      diseases = tibble::tibble(
        symbol = "MLL",
        raw = 4.0,
        source_id = "d",
        source_url = "v"
      )
    )
  )
  # Canonical symbol KMT2A, but the gene collapsed from the alias MLL.
  resolved <- list(
    gene_id = "ENSG1",
    symbol = "KMT2A",
    input_symbols = c("KMT2A", "MLL")
  )
  di <- extract_diseases(resolved, ctx)
  expect_true(di$ok)
  expect_equal(di$raw, 4.0)
})

test_that("cap_seed_symbols() drops NA/blank and caps by seed priority", {
  data <- list(
    ot_targets = tibble::tibble(
      symbol = c("AAA", "BBB", "CCC"),
      raw = c(0.9, 0.1, 0.5)
    ),
    panelapp = tibble::tibble(symbol = "BBB", raw = 1.0)
  )
  syms <- c("AAA", "BBB", "CCC", NA_character_, "")
  # Cap to 2: BBB (0.1 OT + 1.0 PanelApp = 1.1) and AAA (0.9) beat CCC (0.5).
  kept <- cap_seed_symbols(syms, data, max_seed = 2)
  expect_equal(kept, c("BBB", "AAA"))
  # Under the cap: deduped, NA/blank stripped, order preserved.
  all_kept <- cap_seed_symbols(syms, data, max_seed = 10)
  expect_setequal(all_kept, c("AAA", "BBB", "CCC"))
  expect_false(any(is.na(all_kept)))
})

test_that("enrich_genes() keeps a seed-backed signal for an unresolved gene", {
  # A PanelApp GREEN gene that MyGene could not resolve must still surface its
  # already-fetched, symbol-keyed seed evidence instead of being blanked.
  resolved <- tibble::tibble(
    gene_id = "UNRESOLVED:GENEX",
    symbol = "GENEX",
    entrez = NA_character_,
    resolved = FALSE,
    input_symbols = list("GENEX"),
    input_lists = list("disease: X")
  )
  reg <- list(genescout_signal(
    "panelapp",
    "PanelApp confidence",
    "Genomics England PanelApp",
    extractor = extract_panelapp,
    normalize = normalize_identity,
    weight = 1,
    role = "evidence",
    seed_key = "panelapp"
  ))
  ctx <- list(
    disease = list(id = "X", name = "X"),
    seed_data = list(
      panelapp = tibble::tibble(
        symbol = "GENEX",
        raw = 1.0,
        source_id = "PanelApp:panel:1:GENEX",
        source_url = "u"
      )
    )
  )
  row <- enrich_genes(resolved, reg, context = ctx)$signals_long
  expect_true(row$present[row$signal_key == "panelapp"])
  expect_equal(row$raw[row$signal_key == "panelapp"], 1.0)
})

test_that("enrich_genes() still skips LIVE signals for an unresolved gene", {
  # Only seed-backed (offline) signals are rescued; a live signal with no seed_key
  # is never even invoked for an unresolved gene, so no network call fires on a
  # junk token. A call counter proves the extractor was skipped (not just caught).
  calls <- new.env()
  calls$n <- 0L
  resolved <- tibble::tibble(
    gene_id = "UNRESOLVED:JUNK",
    symbol = "JUNK",
    entrez = NA_character_,
    resolved = FALSE,
    input_symbols = list("JUNK"),
    input_lists = list("mine")
  )
  reg <- list(genescout_signal(
    "live",
    "Live",
    "Some API",
    extractor = function(resolved, context = list()) {
      calls$n <- calls$n + 1L
      signal_miss()
    },
    normalize = normalize_identity,
    weight = 1
  ))
  row <- enrich_genes(resolved, reg)$signals_long
  expect_equal(calls$n, 0L) # extractor never invoked for an unresolved live signal
  expect_false(row$present[row$signal_key == "live"])
})

test_that("extract_ot_assoc() reads the seeded disease targets in discovery", {
  ctx <- list(
    disease = list(id = "MONDO_x", name = "neurofibromatosis type 1"),
    seed_data = list(
      ot_targets = tibble::tibble(
        symbol = "NF1",
        raw = 0.9,
        source_id = "OpenTargets:ENSG:MONDO_x",
        source_url = "https://x"
      )
    )
  )
  res <- extract_ot_assoc(list(gene_id = "ENSG1", symbol = "NF1"), ctx)
  expect_true(res$ok)
  expect_equal(res$raw, 0.9)
  expect_true(nrow(res$evidence) >= 1)
  # a gene not among the disease's associated targets misses
  miss <- extract_ot_assoc(list(gene_id = "ENSG2", symbol = "XYZ"), ctx)
  expect_false(miss$ok)
})

test_that("extract_panelapp() / extract_diseases() read seed_data", {
  ctx <- list(
    seed_data = list(
      panelapp = tibble::tibble(
        symbol = "NF1",
        raw = 1.0,
        source_id = "p",
        source_url = "u"
      ),
      diseases = tibble::tibble(
        symbol = "NF1",
        raw = 4.0,
        source_id = "d",
        source_url = "v"
      )
    )
  )
  pa <- extract_panelapp(list(gene_id = "ENSG1", symbol = "NF1"), ctx)
  expect_true(pa$ok)
  expect_equal(pa$raw, 1.0)
  di <- extract_diseases(list(gene_id = "ENSG1", symbol = "NF1"), ctx)
  expect_true(di$ok)
  expect_equal(di$raw, 4.0)
  # no seed_data -> miss (never runs outside discovery mode)
  expect_false(
    extract_panelapp(list(gene_id = "ENSG1", symbol = "NF1"), list())$ok
  )
})

test_that("genescout_signal_registry(disease_mode) appends panelapp + diseases", {
  rubric <- load_rubric(test_path("..", "..", "rubric.yml"))
  disease_keys <- vapply(
    genescout_signal_registry(rubric, disease_mode = TRUE),
    function(s) s$key,
    character(1)
  )
  enrich_keys <- vapply(
    genescout_signal_registry(rubric),
    function(s) s$key,
    character(1)
  )
  expect_true(all(c("panelapp", "diseases") %in% disease_keys))
  expect_false(any(c("panelapp", "diseases") %in% enrich_keys))
})

test_that("run_enrich() seeds candidate genes from an injected seeder", {
  stub_seeder <- function(disease, ...) {
    list(
      symbols = c("NF1", "TP53"),
      data = list(
        ot_targets = tibble::tibble(
          symbol = c("NF1", "TP53"),
          raw = c(0.9, 0.4),
          source_id = c("OT:1", "OT:2"),
          source_url = c("u", "v")
        )
      )
    )
  }
  reg <- list(genescout_signal(
    "ot_assoc",
    "OT",
    "Open Targets",
    extractor = extract_ot_assoc,
    normalize = normalize_identity,
    weight = 1
  ))
  enr <- run_enrich(
    list(), # no user genes -> pure discovery
    context = list(disease = list(id = "MONDO_x", name = "NF1")),
    registry = reg,
    resolver = stub_resolver,
    seeder = stub_seeder
  )
  ranked <- rank_result(enr)
  expect_setequal(ranked$genes$symbol, c("NF1", "TP53"))
  expect_equal(ranked$genes$symbol[1], "NF1") # OT 0.9 > 0.4
  # the seeded genes carry the disease label in their provenance
  expect_true(any(grepl("disease", unlist(ranked$genes$input_lists))))
})

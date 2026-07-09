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

test_that("candid_signal_registry(disease_mode) appends panelapp + diseases", {
  rubric <- load_rubric(test_path("..", "..", "rubric.yml"))
  disease_keys <- vapply(
    candid_signal_registry(rubric, disease_mode = TRUE),
    function(s) s$key,
    character(1)
  )
  enrich_keys <- vapply(
    candid_signal_registry(rubric),
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
  reg <- list(candid_signal(
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

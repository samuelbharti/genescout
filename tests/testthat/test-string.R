# STRING within-list connectivity - offline edge parser, connectivity math, and
# the network-fill signal. No network (the fetch is injected).

test_that("string_network_parse() distills edges to gene_a / gene_b / score", {
  edges <- string_network_parse(read_fixture("string_network.json"))
  expect_equal(nrow(edges), 7)
  expect_true(all(c("gene_a", "gene_b", "score") %in% names(edges)))
  tp53_cdkn2a <- edges[edges$gene_a == "TP53" & edges$gene_b == "CDKN2A", ]
  expect_equal(tp53_cdkn2a$score, 0.999)
})

test_that("string_network_parse() returns an empty frame for no edges", {
  expect_equal(nrow(string_network_parse(list())), 0)
  expect_equal(nrow(string_network_parse(NULL)), 0)
})

test_that("string_connectivity() counts within-list partners; isolates score 0", {
  edges <- string_network_parse(read_fixture("string_network.json"))
  syms <- c("TP53", "NF1", "SUZ12", "CDKN2A", "EGFR", "TTN")
  conn <- string_connectivity(edges, syms)
  deg <- stats::setNames(conn$degree, conn$symbol)
  expect_equal(deg[["TP53"]], 4L) # SUZ12, NF1, EGFR, CDKN2A
  expect_equal(deg[["NF1"]], 3L)
  expect_equal(deg[["EGFR"]], 3L)
  expect_equal(deg[["CDKN2A"]], 3L)
  expect_equal(deg[["SUZ12"]], 1L) # only TP53
  expect_equal(deg[["TTN"]], 0L) # the isolated passenger - no interactions
  # partners are the actual within-list neighbours, sorted.
  expect_equal(conn$partners[[which(conn$symbol == "SUZ12")]], "TP53")
})

test_that("string_connectivity() honours the confidence threshold", {
  edges <- string_network_parse(read_fixture("string_network.json"))
  syms <- c("TP53", "NF1", "SUZ12", "CDKN2A", "EGFR")
  # At >= 0.95 only TP53-CDKN2A (0.999) survives.
  conn <- string_connectivity(edges, syms, min_score = 0.95)
  deg <- stats::setNames(conn$degree, conn$symbol)
  expect_equal(deg[["TP53"]], 1L)
  expect_equal(deg[["CDKN2A"]], 1L)
  expect_equal(deg[["NF1"]], 0L)
})

test_that("string_connectivity() ignores partners not in the candidate set", {
  edges <- string_network_parse(read_fixture("string_network.json"))
  # Drop EGFR from the set: TP53's EGFR edge must not count.
  conn <- string_connectivity(edges, c("TP53", "NF1", "SUZ12", "CDKN2A"))
  deg <- stats::setNames(conn$degree, conn$symbol)
  expect_equal(deg[["TP53"]], 3L) # SUZ12, NF1, CDKN2A (EGFR excluded)
  expect_false("EGFR" %in% conn$symbol)
})

test_that("string_network() needs at least two usable symbols", {
  expect_false(string_network("TP53")$ok) # one gene: no network
  expect_false(string_network(c("", NA))$ok) # nothing usable
})

test_that("enrich_network_signals() nudges connected genes, leaves isolates alone", {
  resolved <- tibble::tibble(
    gene_id = c("G_TP53", "G_NF1", "G_TTN"),
    symbol = c("TP53", "NF1", "TTN"),
    resolved = c(TRUE, TRUE, TRUE)
  )
  registry <- list(string_signal(list(midpoints = list(string = 3))))
  fake_fetch <- function(symbols, ...) {
    list(
      ok = TRUE,
      edges = string_network_parse(read_fixture("string_network.json")),
      queried = symbols,
      source_url = "https://string-db.org/cgi/network?x"
    )
  }
  out <- enrich_network_signals(
    resolved,
    registry,
    fetch_network = fake_fetch
  )
  sig <- out$signals_long
  # TP53 and NF1 are connected (present); TTN is isolated (not present).
  expect_true(sig$present[sig$symbol == "TP53"])
  expect_true(sig$present[sig$symbol == "NF1"])
  expect_false(sig$present[sig$symbol == "TTN"])
  # A queried gene has a measured raw degree (TTN's genuine isolate is a real 0).
  expect_equal(sig$raw[sig$symbol == "TTN"], 0)
  # A connected gene emits grounded interaction evidence; the isolate emits none.
  expect_true(all(out$evidence_long$domain == "interaction"))
  expect_true(any(grepl("TP53", out$evidence_long$source_id)))
  expect_false(any(grepl("TTN", out$evidence_long$source_id)))
})

test_that("enrich_network_signals() emits NA (not 0) when the STRING fetch fails", {
  # A failed/absent network must read as 'no data' (NA -> renders '—'), never as a
  # measured '0 within-list interactions' for every gene (grounding non-negotiable).
  resolved <- tibble::tibble(
    gene_id = c("G_TP53", "G_NF1"),
    symbol = c("TP53", "NF1"),
    resolved = c(TRUE, TRUE)
  )
  registry <- list(string_signal(list(midpoints = list(string = 3))))
  out <- enrich_network_signals(
    resolved,
    registry,
    fetch_network = function(...) list(ok = FALSE, error = "503")
  )
  expect_true(all(is.na(out$signals_long$raw)))
  expect_false(any(out$signals_long$present))
  expect_equal(nrow(out$evidence_long), 0)
})

test_that("string_ids_parse() maps queryItem -> preferredName", {
  m <- string_ids_parse(read_fixture("string_ids.json"))
  expect_true(all(c("query", "preferred", "string_id") %in% names(m)))
  expect_equal(m$preferred[m$query == "SEPTIN9"], "SEPT9")
  expect_equal(m$preferred[m$query == "TP53"], "TP53")
})

test_that("string_reconcile_edges() rewrites preferredName back to the query symbol", {
  # STRING reports the SEPTIN9 edge under its preferredName SEPT9; reconciliation
  # must credit it to SEPTIN9 so the candidate is not scored as an isolate.
  edges <- tibble::tibble(
    gene_a = c("SEPT9", "TP53"),
    gene_b = c("TP53", "MDM2"),
    score = c(0.9, 0.95)
  )
  id_map <- tibble::tibble(
    query = c("SEPTIN9", "TP53", "MDM2"),
    preferred = c("SEPT9", "TP53", "MDM2"),
    string_id = c("9606.a", "9606.b", "9606.c")
  )
  out <- string_reconcile_edges(edges, id_map)
  expect_equal(out$gene_a, c("SEPTIN9", "TP53"))
  # An unmapped endpoint is left untouched; a NULL/empty map is a no-op.
  expect_identical(string_reconcile_edges(edges, NULL), edges)
})

test_that("enrich_network_signals() is a clean no-op without a network signal", {
  resolved <- tibble::tibble(
    gene_id = "G",
    symbol = "TP53",
    resolved = TRUE
  )
  out <- enrich_network_signals(
    resolved,
    list(),
    fetch_network = function(...) {
      stop("must not be called")
    }
  )
  expect_equal(nrow(out$signals_long), 0)
  expect_equal(nrow(out$evidence_long), 0)
})

test_that("run_enrich() appends STRING for a >= 5-token list and audits provenance", {
  # The gate fires at CANDID_STRING_MIN_GENES tokens; the network fetch is injected
  # so this end-to-end path stays offline. Two tokens resolve (NF1, TP53) and
  # interact in the fixture; three are junk and never queried.
  fake_fetch <- function(symbols, ...) {
    list(
      ok = TRUE,
      edges = string_network_parse(read_fixture("string_network.json")),
      queried = symbols,
      source_url = "https://string-db.org/cgi/network?x"
    )
  }
  enr <- run_enrich(
    list(mine = c("NF1", "TP53", "AAA", "BBB", "CCC")),
    registry = stub_registry(),
    resolver = stub_resolver,
    fetch_network = fake_fetch
  )
  expect_true(all(
    c("string", "string_n", "string_present") %in% names(enr$genes)
  ))
  g <- enr$genes
  expect_true(g$string_present[g$symbol == "NF1"])
  expect_true(g$string_present[g$symbol == "TP53"])
  # An unresolved (never-queried) token reads NA, not a measured 0.
  expect_true(is.na(g$string[g$symbol == "AAA"]))
  prov <- vapply(enr$provenance, function(s) s$source, character(1))
  expect_true(any(grepl("STRING", prov)))
})

test_that("run_enrich() does NOT append STRING for a small list (fetch never fires)", {
  enr <- run_enrich(
    list(mine = c("NF1", "TP53")),
    registry = stub_registry(),
    resolver = stub_resolver,
    fetch_network = function(...) {
      stop("STRING must not be queried for a small list")
    }
  )
  expect_false("string" %in% names(enr$genes))
  expect_false("string_n" %in% names(enr$genes))
})

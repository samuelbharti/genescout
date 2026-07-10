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
  # A connected gene emits grounded interaction evidence; the isolate emits none.
  expect_true(all(out$evidence_long$domain == "interaction"))
  expect_true(any(grepl("TP53", out$evidence_long$source_id)))
  expect_false(any(grepl("TTN", out$evidence_long$source_id)))
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

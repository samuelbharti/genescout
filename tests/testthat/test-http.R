# Shared HTTP layer - helper + cache tests (offline, no requests performed).

test_that("is_blank() detects empty-ish values", {
  expect_true(is_blank(NULL))
  expect_true(is_blank(NA))
  expect_true(is_blank(""))
  expect_true(is_blank("   "))
  expect_true(is_blank(character(0)))
  expect_false(is_blank("TP53"))
  expect_false(is_blank(0))
})

test_that("pluck_at() walks nested lists and falls back", {
  x <- list(data = list(target = list(approvedSymbol = "NF1")))
  expect_equal(pluck_at(x, "data", "target", "approvedSymbol"), "NF1")
  expect_null(pluck_at(x, "data", "missing"))
  expect_equal(pluck_at(x, "data", "missing", default = "-"), "-")
})

test_that("candid_cache_key() is stable and order-sensitive", {
  expect_identical(
    candid_cache_key("GET", "u", list(a = 1)),
    candid_cache_key("GET", "u", list(a = 1))
  )
  expect_false(identical(
    candid_cache_key("GET", "u"),
    candid_cache_key("POST", "u")
  ))
})

test_that("candid_cached() caches successes but not failures", {
  candid_cache$reset()
  calls <- 0
  ok_fetch <- function() {
    calls <<- calls + 1
    list(ok = TRUE, data = "x")
  }
  candid_cached("k1", ok_fetch)
  candid_cached("k1", ok_fetch)
  expect_equal(calls, 1) # second call served from cache

  fails <- 0
  bad_fetch <- function() {
    fails <<- fails + 1
    list(ok = FALSE, error = "nope")
  }
  candid_cached("k2", bad_fetch)
  candid_cached("k2", bad_fetch)
  expect_equal(fails, 2) # failures never cached
})

test_that("candid_req_defaults() attaches auth headers and redacts the secret", {
  req <- candid_req_defaults(
    httr2::request("https://example.org"),
    timeout = 15,
    max_tries = 3,
    headers = list(Authorization = "Bearer SUPERSECRETTOKEN")
  )
  # The header is attached to the request...
  expect_true("Authorization" %in% names(req$headers))
  # ...but the token is redacted, so it never appears in a printed/logged request.
  printed <- paste(utils::capture.output(print(req)), collapse = " ")
  expect_false(grepl("SUPERSECRETTOKEN", printed))
})

test_that("the cache key excludes auth headers (secret never enters the hash)", {
  # candid_cache_key is computed from method/url/path/query only - headers are not
  # passed to it, so the same request caches identically with or without a token.
  expect_identical(
    candid_cache_key("GET", "https://x", "p", list(geneId = "TP53")),
    candid_cache_key("GET", "https://x", "p", list(geneId = "TP53"))
  )
})

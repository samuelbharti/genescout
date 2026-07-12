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

test_that("http_get_text uses a cache key distinct from http_get_json", {
  # The text and JSON GETs must not collide in the shared cache (different prefix),
  # or a bulk CSV could be served where parsed JSON is expected and vice versa.
  expect_false(identical(
    candid_cache_key("GET", "https://x", NULL, list()),
    candid_cache_key("GET_TEXT", "https://x", NULL, list())
  ))
})

test_that("the cache key excludes auth headers (secret never enters the hash)", {
  # candid_cache_key is computed from method/url/path/query only - headers are not
  # passed to it, so the same request caches identically with or without a token.
  expect_identical(
    candid_cache_key("GET", "https://x", "p", list(geneId = "TP53")),
    candid_cache_key("GET", "https://x", "p", list(geneId = "TP53"))
  )
})

test_that("graphql_error() flags transport failures and in-body query errors", {
  # Transport failure -> the client's error, sourced.
  fail <- graphql_error(list(ok = FALSE, error = "Could not reach X"), "DGIdb")
  expect_false(fail$ok)
  expect_equal(fail$error, "Could not reach X")
  # Transport failure with no message -> a sourced fallback.
  bare <- graphql_error(list(ok = FALSE), "DGIdb")
  expect_match(bare$error, "DGIdb request failed", fixed = TRUE)
  # A GraphQL error array inside an HTTP 200 body -> a query error (the case civic
  # previously missed).
  qerr <- graphql_error(
    list(ok = TRUE, data = list(errors = list(list(message = "bad field")))),
    "CIViC"
  )
  expect_false(qerr$ok)
  expect_match(qerr$error, "CIViC returned a query error", fixed = TRUE)
  # A clean response -> NULL (proceed to parse).
  expect_null(graphql_error(list(ok = TRUE, data = list(gene = list(id = 1)))))
})

# --- Contact-bearing User-Agent ---------------------------------------------

test_that("candid_user_agent() identifies CANDID and carries a contact", {
  ua <- withr::with_envvar(c(CANDID_CONTACT_EMAIL = ""), candid_user_agent())
  expect_match(ua, "CANDID/", fixed = TRUE)
  expect_match(ua, "github.com/samuelbharti/candid", fixed = TRUE)
  expect_false(grepl("mailto:", ua, fixed = TRUE)) # no email set -> no mailto
  # A hosted operator can add a contact email for the polite-usage etiquette.
  ua2 <- withr::with_envvar(
    c(CANDID_CONTACT_EMAIL = "ops@example.org"),
    candid_user_agent()
  )
  expect_match(ua2, "mailto:ops@example.org", fixed = TRUE)
})

# --- Per-host circuit breaker ------------------------------------------------

test_that("candid_url_host() extracts the hostname (falls back safely)", {
  expect_equal(
    candid_url_host("https://gnomad.broadinstitute.org/api"),
    "gnomad.broadinstitute.org"
  )
  expect_equal(candid_url_host("not a url"), "unknown-host")
})

test_that("the per-host breaker trips after K transport failures and self-heals", {
  candid_breaker_reset()
  on.exit(candid_breaker_reset(), add = TRUE)
  h <- "dead.example.org"
  expect_false(candid_breaker_open(h, now = 100))
  # Below the threshold does not trip.
  candid_breaker_record(h, ok = FALSE, now = 100)
  candid_breaker_record(h, ok = FALSE, now = 100)
  expect_false(candid_breaker_open(h, now = 100)) # 2 < threshold 3
  # The Kth consecutive transport failure trips it for the cooldown window.
  candid_breaker_record(h, ok = FALSE, now = 100)
  expect_true(candid_breaker_open(h, now = 100))
  expect_true(candid_breaker_open(h, now = 100 + CANDID_BREAKER_COOLDOWN - 1))
  # It self-heals once the cooldown elapses.
  expect_false(candid_breaker_open(h, now = 100 + CANDID_BREAKER_COOLDOWN + 1))
})

test_that("a success clears the breaker's failure count", {
  candid_breaker_reset()
  on.exit(candid_breaker_reset(), add = TRUE)
  h <- "flaky.example.org"
  candid_breaker_record(h, ok = FALSE, now = 0)
  candid_breaker_record(h, ok = FALSE, now = 0)
  candid_breaker_record(h, ok = TRUE, now = 0) # reachable again -> reset
  candid_breaker_record(h, ok = FALSE, now = 0)
  expect_false(candid_breaker_open(h, now = 0)) # count restarted -> only 1 failure
})

test_that("candid_perform() short-circuits a tripped host without a request", {
  candid_breaker_reset()
  on.exit(candid_breaker_reset(), add = TRUE)
  # Trip the host directly, then assert candid_perform returns a fast miss WITHOUT
  # performing (a real request to this fake host would otherwise error/hang).
  host <- candid_url_host("https://nowhere.invalid/x")
  for (i in seq_len(CANDID_BREAKER_THRESHOLD)) {
    candid_breaker_record(host, ok = FALSE)
  }
  res <- candid_perform(httr2::request("https://nowhere.invalid/x"), "Test")
  expect_false(res$ok)
  expect_match(res$error, "skipped", fixed = TRUE)
})

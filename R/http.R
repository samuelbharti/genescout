# Shared HTTP wrapper. Every tool client routes through here so timeout, retry,
# and caching behavior live in exactly one place.
#
# Contract (to implement in the Phase 0 slice):
#   - timeout on every request; a single retry on transient failure;
#   - a 30-minute in-process cache on SUCCESSFUL responses only (never cache
#     failures);
#   - raise a typed `candid_http_error` condition on failure (never return a
#     half-parsed blob).
#
# Built on {httr2}. No {ellmer} imports here - clients must be callable and
# testable in plain R.

# GET a URL with query params and parse the JSON body to an R list.
http_get_json <- function(url, query = list(), headers = list(), ...) {
  not_implemented("http_get_json (shared httr2 wrapper)")
}

# POST a JSON body (e.g. GraphQL queries) and parse the JSON response.
http_post_json <- function(url, body, headers = list(), ...) {
  not_implemented("http_post_json (shared httr2 wrapper)")
}

# Construct the typed error condition used across tool clients.
candid_http_error <- function(
  message,
  status = NA_integer_,
  url = NA_character_
) {
  structure(
    class = c("candid_http_error", "error", "condition"),
    list(message = message, status = status, url = url)
  )
}

test_that("app_version() returns the current version string", {
  expect_type(app_version(), "character")
  expect_match(app_version(), "^[0-9]+[.][0-9]+[.][0-9]+$")
})

test_that("safe_read_rds() returns the default for a missing file", {
  expect_null(safe_read_rds(tempfile()))
  expect_identical(safe_read_rds(tempfile(), default = "fallback"), "fallback")
})

test_that("not_implemented() signals a catchable candid condition", {
  expect_error(not_implemented("thing"), class = "candid_not_implemented")
  err <- tryCatch(not_implemented("thing"), condition = function(e) e)
  expect_match(conditionMessage(err), "not implemented yet")
})

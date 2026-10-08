# Background execution of the AI steps (R/llm_offload.R).
#
# Under testthat the AI steps run in-process, so the rest of the suite never
# starts a worker. The pool tests below lift that switch on purpose to check what
# issue #47 is about: a step returns at once, and the R process never waits for
# it. They skip the engine bootstrap and send small functions, so each takes
# about a second; one test bootstraps the real engine.

# Start a pool for one test, and close it when the test ends.
local_llm_pool <- function(
  workers = 1L,
  bootstrap = FALSE,
  env = parent.frame()
) {
  withr::local_envvar(TESTTHAT = "", .local_envir = env)
  withr::local_options(
    genescout.llm.workers = workers,
    genescout.llm.bootstrap = bootstrap,
    .local_envir = env
  )
  suppressMessages(genescout_llm_pool_start())
  withr::defer(genescout_llm_pool_close(), envir = env)
}

# A function sent to a worker carries its environment along. Test functions get
# the global environment, like the app's step functions have.
in_global <- function(f) {
  environment(f) <- globalenv()
  f
}

sleepy <- in_global(function(seconds) {
  Sys.sleep(seconds)
  "done"
})

# Wait in this process for a promise to settle, for at most `timeout` seconds.
promise_value <- function(p, timeout = 5) {
  state <- new.env()
  state$done <- FALSE
  promises::then(
    p,
    onFulfilled = function(v) {
      state$value <- v
      state$done <- TRUE
    },
    onRejected = function(e) {
      state$error <- e
      state$done <- TRUE
    }
  )
  deadline <- Sys.time() + timeout
  while (!state$done && Sys.time() < deadline) {
    later::run_now(0.05)
  }
  as.list(state)
}

# Poll `condition()` until it is TRUE, for at most `timeout` seconds.
wait_until <- function(condition, timeout = 15) {
  deadline <- Sys.time() + timeout
  while (!isTRUE(condition()) && Sys.time() < deadline) {
    Sys.sleep(0.05)
  }
  isTRUE(condition())
}

pool_info <- function() mirai::info(.compute = GENESCOUT_LLM_COMPUTE)

# --- In-process path ------------------------------------------------------------

test_that("genescout_llm_offload_available() is off under testthat", {
  # testthat sets TESTTHAT=true, the hard off-switch, so the suite never offloads.
  expect_false(genescout_llm_offload_available())
})

test_that("a step runs in-process as a promise when offloading is off", {
  p <- genescout_llm_submit(function(a, b) a + b, 40, 2)
  expect_true(promises::is.promise(p))
  expect_equal(promise_value(p)$value, 42)

  scale_by <- function(x, scale = 1) x * scale
  expect_equal(
    promise_value(genescout_llm_submit(scale_by, 21, scale = 2))$value,
    42
  )

  # An error in the step becomes a rejected promise, not an error here.
  failed <- promise_value(genescout_llm_submit(function() stop("boom")))
  expect_match(conditionMessage(failed$error), "boom")
})

test_that("the opt-out option keeps steps in-process even with mirai", {
  skip_if_not_installed("mirai")
  withr::local_envvar(TESTTHAT = "")
  expect_true(genescout_llm_offload_available())
  withr::local_options(genescout.llm.offload = FALSE)
  expect_false(genescout_llm_offload_available())
  p <- genescout_llm_submit(function() 42)
  expect_true(promises::is.promise(p))
  expect_equal(promise_value(p)$value, 42)
})

test_that("pool size and time limit come from the option, else the variable", {
  withr::local_options(
    genescout.llm.workers = NULL,
    genescout.llm.timeout_ms = NULL
  )
  withr::local_envvar(GENESCOUT_LLM_WORKERS = "", GENESCOUT_LLM_TIMEOUT_MS = "")
  expect_equal(genescout_llm_workers(), GENESCOUT_LLM_WORKERS)
  expect_equal(genescout_llm_timeout_ms(), GENESCOUT_LLM_TIMEOUT_MS)

  withr::local_envvar(
    GENESCOUT_LLM_WORKERS = "3",
    GENESCOUT_LLM_TIMEOUT_MS = "500"
  )
  expect_equal(genescout_llm_workers(), 3L)
  expect_equal(genescout_llm_timeout_ms(), 500)

  withr::local_options(genescout.llm.workers = 1L)
  expect_equal(genescout_llm_workers(), 1L)

  withr::local_envvar(GENESCOUT_LLM_WORKERS = "none")
  withr::local_options(genescout.llm.workers = NULL)
  expect_equal(genescout_llm_workers(), GENESCOUT_LLM_WORKERS)
})

# --- Pool path: the behavior issue #47 asks for -------------------------------

test_that("a background step returns at once, and this process does not wait", {
  skip_if_not_installed("mirai")
  local_llm_pool()
  started <- Sys.time()
  m <- genescout_llm_submit(sleepy, 2)
  expect_lt(as.numeric(difftime(Sys.time(), started, units = "secs")), 0.5)
  expect_s3_class(m, "mirai")
  expect_true(mirai::unresolved(m))
  expect_equal(m[], "done")
})

test_that("steps from two sessions share the pool without stopping each other", {
  skip_if_not_installed("mirai")
  # The old code started and closed a worker on every call, so a second call
  # killed the first one's worker.
  local_llm_pool(workers = 2L)
  first <- genescout_llm_submit(sleepy, 1)
  second <- genescout_llm_submit(sleepy, 1)
  expect_equal(first[], "done")
  expect_equal(second[], "done")
})

test_that("a step that runs past the time limit is stopped, and not run again", {
  skip_if_not_installed("mirai")
  local_llm_pool()
  withr::local_options(genescout.llm.timeout_ms = 300)
  started <- Sys.time()
  value <- genescout_llm_submit(sleepy, 3)[]
  expect_true(mirai::is_error_value(value))
  expect_equal(as.integer(value), 5L)
  # An in-process re-run would have taken 3 seconds.
  expect_lt(as.numeric(difftime(Sys.time(), started, units = "secs")), 2.5)
})

test_that("a cancelled step stops, and the pool keeps working", {
  skip_if_not_installed("mirai")
  local_llm_pool()
  m <- genescout_llm_submit(sleepy, 5)
  expect_true(wait_until(function() pool_info()[["executing"]] >= 1))
  expect_true(genescout_llm_cancel(m))
  expect_equal(as.integer(m[]), 20L)
  expect_equal(genescout_llm_submit(sleepy, 0)[], "done")
})

test_that("a pool whose worker stopped is started again on the next step", {
  skip_if_not_installed("mirai")
  local_llm_pool()
  quits <- in_global(function() quit(save = "no", status = 1))
  expect_equal(as.integer(genescout_llm_submit(quits)[]), 19L)
  expect_true(wait_until(function() pool_info()[["connections"]] == 0))
  expect_message(
    m <- genescout_llm_submit(sleepy, 0),
    "started 1 background worker"
  )
  expect_equal(m[], "done")
})

test_that("the engine loads on a worker, and a real step runs there", {
  skip_if_not_installed("mirai")
  withr::local_envvar(
    GENESCOUT_APP_ROOT = normalizePath(test_path("..", ".."), winslash = "/")
  )
  local_llm_pool(bootstrap = TRUE)
  # An empty ranking returns before the step reads its config or calls a
  # model, so this needs no network and no API key.
  out <- genescout_llm_submit(curate_gene_list, list(genes = NULL))[]
  expect_false(mirai::is_error_value(out))
  expect_false(attr(out, "ai_used"))
  expect_match(attr(out, "message"), "No ranked genes")
})

# --- Reading a finished step ----------------------------------------------------

test_that("genescout_llm_outcome() reads a finished step as a value or a message", {
  fake_task <- function(status, value = NULL, error = NULL) {
    list(
      status = function() status,
      result = function() if (is.null(error)) value else stop(error)
    )
  }
  fake_mirai <- function(data) structure(list(data = data), class = "mirai")
  code <- function(n) structure(n, class = "errorValue")

  expect_null(genescout_llm_outcome(fake_task("initial"), NULL))
  expect_null(genescout_llm_outcome(fake_task("running"), NULL))

  done <- genescout_llm_outcome(
    fake_task("success", value = 42),
    fake_mirai(42)
  )
  expect_true(done$ok)
  expect_equal(done$value, 42)

  timed_out <- genescout_llm_outcome(
    fake_task("error", error = "5 | Timed out"),
    fake_mirai(code(5L))
  )
  expect_false(timed_out$ok)
  expect_match(timed_out$message, "ran longer than 10 minutes")
  withr::with_options(list(genescout.llm.timeout_ms = 5000), {
    expect_match(
      genescout_llm_failure(code(5L)),
      "ran longer than 5 seconds"
    )
  })

  stopped <- genescout_llm_outcome(fake_task("error"), fake_mirai(code(19L)))
  expect_match(stopped$message, "worker stopped")

  # A step cancelled on purpose fails quietly: no message to show.
  cancelled <- genescout_llm_outcome(fake_task("error"), fake_mirai(code(20L)))
  expect_false(cancelled$ok)
  expect_null(cancelled$message)

  # mirai passes an interrupt through as a "success"; it is still a failure.
  interrupt <- structure("", class = c("miraiInterrupt", "errorValue"))
  interrupted <- genescout_llm_outcome(
    fake_task("success", value = interrupt),
    fake_mirai(interrupt)
  )
  expect_false(interrupted$ok)
  expect_match(interrupted$message, "interrupted")

  # The in-process path has no mirai: the task's own error is the message.
  failed <- genescout_llm_outcome(fake_task("error", error = "boom"), NULL)
  expect_false(failed$ok)
  expect_equal(failed$message, "boom")
})

# The shared chrome helpers (version, footer, mascot, click-info popover) render
# the metadata and markup the redesigned shell relies on.

render_html <- function(tag) {
  as.character(htmltools::renderTags(tag)$html)
}

test_that("genescout_version returns the DESCRIPTION version", {
  v <- genescout_version()
  expect_true(is.character(v) && length(v) == 1 && nzchar(v))
  expect_true(grepl("[0-9]", v))
})

test_that("footer carries version, license, research-use note, and the repo link", {
  h <- render_html(genescout_footer())
  expect_true(grepl("gs-footer", h, fixed = TRUE))
  expect_true(grepl(paste0("v", genescout_version()), h, fixed = TRUE))
  expect_true(grepl("MIT License", h, fixed = TRUE))
  expect_true(grepl("Research use only", h, fixed = TRUE))
  expect_true(grepl(GENESCOUT_REPO_URL, h, fixed = TRUE))
})

test_that("gs_info renders a click-to-open info popover with its body", {
  h <- render_html(gs_info("explain ", tags$b("this")))
  expect_true(grepl("gs-info", h, fixed = TRUE))
  expect_true(grepl("explain", h, fixed = TRUE))
})

test_that("the mascot points at the bundled SVG", {
  h <- render_html(genescout_mascot(30))
  expect_true(grepl("img/mascot.svg", h, fixed = TRUE))
})

test_that("gs_page wraps content in the shared page container", {
  h <- render_html(gs_page(tags$p("hi")))
  expect_true(grepl("gs-page", h, fixed = TRUE))
  expect_true(grepl("hi", h, fixed = TRUE))
})

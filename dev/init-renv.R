# dev/init-renv.R
# Bootstrap renv for GeneScout: install the app's dependencies and write renv.lock.
# Run once from the repo root:  Rscript dev/init-renv.R
# Thereafter, a fresh clone restores with:  Rscript -e 'renv::restore()'

if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv", repos = "https://cloud.r-project.org")
}

if (!file.exists("renv.lock")) {
  message("Initializing renv and taking initial snapshot...")
  renv::init(bare = TRUE)
  # GeneScout runtime dependencies (mirrors DESCRIPTION Imports/Suggests).
  renv::install(c(
    "shiny",
    "bslib",
    "brand.yml",
    "ellmer",
    "shinychat",
    "httr2",
    "jsonlite",
    "yaml",
    "dplyr",
    "tibble",
    "purrr",
    "DT",
    "htmltools",
    "testthat",
    "httptest2"
  ))
  renv::snapshot()
  message(
    "renv initialized and renv.lock written. Review renv.lock before committing."
  )
} else {
  message("renv.lock already exists. Use renv::restore() to restore packages.")
}

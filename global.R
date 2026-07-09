# CANDID — global setup.
# Loads libraries, sources app components, and initializes the provider/model
# configuration and the available disease contexts. Runs once at app startup.
library(shiny)
library(bslib)

# Optionally theme base/ggplot/lattice output to match the app theme. Activates
# only if the {thematic} package is installed, so it adds no hard dependency.
if (requireNamespace("thematic", quietly = TRUE)) {
  thematic::thematic_shiny(font = "auto")
}

source("R/load_components.R")

# Provider/model configuration (roles -> provider + model), read from config.yml.
# Never hardcode model strings in engine logic; read them from here.
candid_config <- load_config()

# Disease contexts available to the UI (named list, keyed by context id).
candid_contexts <- list_contexts()

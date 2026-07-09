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
# Never hardcode model strings in engine logic; read them from here. Reserved for
# the later subjective-ranking agent; the deterministic pipeline uses no LLM.
candid_config <- load_config()

# The signal registry (which sources contribute to the composite rank, and their
# weights), built once from rubric.yml. Passed into run_review() by the app.
candid_registry <- candid_signal_registry()

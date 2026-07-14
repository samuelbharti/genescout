# GeneScout — global setup.
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
genescout_config <- load_config()

# The signal registries (which sources contribute to the composite rank, and
# their weights), built once from rubric.yml. `genescout_registry` is the default
# enrichment set; `genescout_registry_disease` adds the disease-keyed PanelApp and
# DISEASES signals for discovery mode. The app picks one per run by whether a
# disease context is set.
genescout_registry <- genescout_signal_registry()
genescout_registry_disease <- genescout_signal_registry(disease_mode = TRUE)

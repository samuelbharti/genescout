# Configuration loader. Reads config.yml (provider + per-role model map) so the
# rest of the engine never hardcodes provider/model strings.
#
# config.yml shape:
#   default:
#     provider: anthropic
#     models:
#       orchestrator: <model>
#       caveats:      <model>
#       specialist:   <model>

# Load the active configuration profile as a plain list.
load_config <- function(path = "config.yml", profile = "default") {
  if (!file.exists(path)) {
    stop("Config file not found: ", path, call. = FALSE)
  }
  cfg <- yaml::read_yaml(path)
  if (is.null(cfg[[profile]])) {
    stop("Config profile not found: ", profile, call. = FALSE)
  }
  cfg[[profile]]
}

# Resolve the model id for a pipeline role (orchestrator, caveats, specialist).
model_for <- function(role, config = load_config()) {
  model <- config$models[[role]]
  if (is.null(model)) {
    stop("No model configured for role: ", role, call. = FALSE)
  }
  model
}

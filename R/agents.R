# Agent construction (ellmer). Builds the orchestrator and the three specialist
# subagents as ellmer Chat objects, each seeded with its own system prompt and a
# restricted set of registered R tools. Provider/model come from config (never
# hardcoded); "any provider" is a config change, not a code change.
#
# The evidence schema every specialist must return is defined by
# evidence_schema(): each item carries a `source_id`, which is what the citation
# gate (see citation_gate.R) enforces.

# Roles -> which tool clients they may call. The specialist only ever sees its
# own allowlist, keeping contexts isolated.
specialist_tools <- list(
  `variant-effect` = c("vep_consequence", "gnomad_frequency", "clinvar_lookup"),
  `pathway-disease` = c(
    "gene_disease_assoc",
    "reactome_pathways",
    "pager_enrichment"
  ),
  literature = c("europepmc_search", "pubtator_annotations")
)

# The structured-output schema for a specialist's distilled evidence. Every
# evidence item must include a non-empty `source_id`.
evidence_schema <- function() {
  not_implemented("evidence_schema (ellmer type_object schema)")
}

# Build a specialist Chat: system prompt from prompts/<role>.md, model from
# config, and the role's tools registered on the chat.
build_specialist <- function(role, config = load_config()) {
  not_implemented(sprintf("build_specialist('%s')", role))
}

# Build the orchestrator Chat that parses input, routes to specialists, and
# assembles results.
build_orchestrator <- function(config = load_config()) {
  not_implemented("build_orchestrator")
}

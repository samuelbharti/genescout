# Variant-effect clients - Ensembl VEP, gnomAD, ClinVar.
# Endpoints (see docs/data_sources.md):
#   Ensembl VEP  https://rest.ensembl.org
#   gnomAD       https://gnomad.broadinstitute.org/api  (GraphQL)
#   ClinVar      https://eutils.ncbi.nlm.nih.gov  (E-utilities)
# All used as research evidence, never as a clinical call.
# Pure clients through the shared HTTP wrapper; no {ellmer} imports.

# Predicted functional consequence of a variant (Ensembl VEP).
vep_consequence <- function(variant) {
  not_implemented("vep_consequence (Ensembl VEP)")
}

# Population allele frequency for a variant (gnomAD) - rarity signal.
gnomad_frequency <- function(variant) {
  not_implemented("gnomad_frequency (gnomAD)")
}

# Known ClinVar records for a variant (evidence, not a diagnosis).
clinvar_lookup <- function(variant) {
  not_implemented("clinvar_lookup (ClinVar via E-utilities)")
}

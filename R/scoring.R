# Composite technical ranking.
#
# Each source contributes a normalized [0,1] signal; the composite is a WEIGHTED
# MEAN across all registry signals, where a missing signal contributes 0 to the
# numerator but its weight stays in the denominator. So a gene supported broadly
# but moderately outranks one that is famous in a single source - this is what
# structurally defeats the familiar-gene bias.
#
# Weights and normalization midpoints live in rubric.yml (edit there to retune -
# no code change). Everything here is pure and deterministic, so rankings are
# reproducible run-to-run and independent of which other genes are in the list.

# Load the ranking rubric (per-signal weights + normalization midpoints).
load_rubric <- function(path = "rubric.yml", profile = "default") {
  if (!file.exists(path)) {
    stop("Rubric file not found: ", path, call. = FALSE)
  }
  cfg <- yaml::read_yaml(path)
  if (is.null(cfg[[profile]])) {
    stop("Rubric profile not found: ", profile, call. = FALSE)
  }
  cfg[[profile]]
}

# --- Normalizers: raw signal -> [0,1]. NA or negative -> 0 (no positive signal).

# Identity clamp, for signals already on a 0-1 scale (e.g. Open Targets score).
normalize_identity <- function(x) {
  x <- ifelse(is.na(x), 0, x)
  pmin(pmax(x, 0), 1)
}

# Saturating x/(x+m): raw = m normalizes to 0.5, with diminishing returns above.
# Absolute (not cohort-relative): adding or removing genes never changes a gene's
# normalized value, so rankings stay reproducible.
normalize_saturating <- function(m) {
  force(m)
  function(x) {
    x <- ifelse(is.na(x) | x < 0, 0, x)
    x / (x + m)
  }
}

# Log-saturating, for heavy-tailed counts (e.g. PMID hits):
# log1p(x) / (log1p(x) + log1p(m)).
normalize_log_saturating <- function(m) {
  force(m)
  k <- log1p(m)
  function(x) {
    x <- ifelse(is.na(x) | x < 0, 0, x)
    l <- log1p(x)
    l / (l + k)
  }
}

# Descending saturating m/(x+m): x = 0 -> 1, x = m -> 0.5, larger x -> 0. For
# "lower is better" signals (e.g. gnomAD LOEUF, where a small value means strong
# loss-of-function constraint) so that every normalized column stays
# higher-is-better and the composite can treat all signals uniformly. NA or
# negative -> 0 (no positive signal). Absolute, so it stays reproducible.
normalize_saturating_desc <- function(m) {
  force(m)
  function(x) {
    out <- m / (x + m)
    ifelse(is.na(x) | x < 0, 0, out)
  }
}

# --- Composite + rank -------------------------------------------------------

# Weighted mean of the normalized per-signal columns (`<key>_n`) over the
# registry, role-aware:
#   - EVIDENCE signals: weight is always in the denominator, so a missing one
#     contributes 0 to the numerator but still divides - breadth is rewarded and
#     a narrow-but-famous gene is structurally beaten by a broadly-supported one.
#   - ANNOTATION signals (e.g. constraint, druggability): weight enters the
#     denominator ONLY when present for that gene, so a missing annotation is
#     neutral (it nudges the score up when available, never penalizes when not).
# `weights` (a named key -> weight vector) overrides the registry weights, which
# is how the live UI sliders re-rank without re-querying. `coverage_bonus`
# optionally rewards genes supported by many EVIDENCE sources.
compute_composite <- function(
  gene_matrix,
  registry,
  weights = NULL,
  coverage_bonus = FALSE
) {
  if (nrow(gene_matrix) == 0) {
    gene_matrix$composite <- numeric()
    return(gene_matrix)
  }
  keys <- vapply(registry, function(s) s$key, character(1))
  roles <- vapply(registry, function(s) s$role %||% "evidence", character(1))
  w <- if (is.null(weights)) {
    vapply(registry, function(s) s$weight, numeric(1))
  } else {
    as.numeric(weights[keys])
  }
  w[is.na(w)] <- 0

  norm <- as.matrix(gene_matrix[, paste0(keys, "_n"), drop = FALSE])
  norm[is.na(norm)] <- 0
  numer <- as.numeric(norm %*% w)

  is_ann <- roles == "annotation"
  denom <- rep(sum(w[!is_ann]), nrow(gene_matrix))
  if (any(is_ann)) {
    pcols <- paste0(keys[is_ann], "_present")
    if (all(pcols %in% names(gene_matrix))) {
      pres <- as.matrix(gene_matrix[, pcols, drop = FALSE])
      pres <- matrix(as.numeric(pres), nrow = nrow(gene_matrix))
      denom <- denom + as.numeric(pres %*% w[is_ann])
    } else {
      # No per-signal presence columns (e.g. a minimal stub matrix): treat
      # annotation weight as always-on, the pre-role behavior.
      denom <- denom + sum(w[is_ann])
    }
  }

  composite <- ifelse(denom > 0, numer / denom, 0)
  if (isTRUE(coverage_bonus)) {
    n_ev <- sum(!is_ann)
    cov <- if (n_ev > 0 && "n_evidence_present" %in% names(gene_matrix)) {
      gene_matrix$n_evidence_present / n_ev
    } else {
      0
    }
    composite <- composite * (0.5 + 0.5 * cov)
  }
  gene_matrix$composite <- composite
  gene_matrix
}

# The coverage-bonus toggle from the rubric, defaulting to FALSE when the rubric
# file is not on the current path (e.g. in unit tests that pass a stub registry).
rubric_coverage_bonus <- function() {
  tryCatch(isTRUE(load_rubric()$coverage_bonus), error = function(e) FALSE)
}

# Deterministic rank by composite (descending); symbol is the stable tie-break.
rank_genes <- function(gene_matrix) {
  if (nrow(gene_matrix) == 0) {
    gene_matrix$rank <- integer()
    return(gene_matrix)
  }
  gene_matrix$rank <- rank(-gene_matrix$composite, ties.method = "min")
  gene_matrix[order(gene_matrix$rank, gene_matrix$symbol), , drop = FALSE]
}

# Grade thresholds on the composite (0-1) - a UI badge only; rank is by composite.
CANDID_GRADE_BREAKS <- c(high = 0.5, moderate = 0.2)

grade_for_score <- function(score) {
  ifelse(
    is.na(score),
    "Insufficient",
    ifelse(
      score >= CANDID_GRADE_BREAKS[["high"]],
      "High",
      ifelse(score >= CANDID_GRADE_BREAKS[["moderate"]], "Moderate", "Low")
    )
  )
}

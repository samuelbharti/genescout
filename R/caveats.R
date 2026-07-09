# Caveats & veto - the anti-familiar-gene-bias override on the composite ranking.
#
# Deterministic and reproducible (same input -> same result); never an LLM in the
# ranking path, so a ranking stays stable run-to-run and independent of the other
# genes in the list. Reads the rubric's caveats block plus optional disease-context
# priors (context$priors), applies each trigger, RECORDS WHY on the candidate, and
# either down-weights the composite (a caveat) or forces the gene to the bottom (a
# veto). The human-readable spec is prompts/scoring-rubric.md.
#
# Implemented triggers (the signals we actually have):
#   - VETO: a recurrent-artifact FLAGS gene (weak evidence of disease relevance
#     regardless of context).
#   - CAVEAT: supported only by a single weak evidence source.
# Two rubric triggers are DEFERRED (documented, not faked) because CANDID does not
# yet pull the signal they need: "common in gnomAD" needs a gene-level allele-
# frequency signal (LOEUF is constraint, not frequency, so it is NOT a substitute),
# and "unrelated-tissue-only" needs a tissue-expression signal. Add the signal
# first, then wire the trigger here.

# Universal recurrent-artifact (FLAGS = FrequentLy mutAted GeneS) fallback, used
# only when the rubric omits a caveats$flags_genes list. The canonical list is
# from Shyr et al. 2014 (BMC Med Genomics 7:64); the rubric ships the tunable copy.
CANDID_DEFAULT_FLAGS <- c(
  "TTN",
  "MUC16",
  "OBSCN",
  "SYNE1",
  "MUC4",
  "FLG"
)

# Resolve the caveats settings from the rubric, with safe defaults when the rubric
# (or its caveats block) is absent - e.g. unit tests that pass a stub registry.
caveat_config <- function(rubric = NULL) {
  rubric <- rubric %||% tryCatch(load_rubric(), error = function(e) list())
  cv <- rubric$caveats %||% list()
  ss <- cv$single_source %||% list()
  list(
    enabled = isTRUE(cv$enabled %||% TRUE),
    flags_genes = toupper(as.character(
      cv$flags_genes %||% CANDID_DEFAULT_FLAGS
    )),
    single_penalty = as.numeric(ss$penalty %||% 0.75),
    single_max_norm = as.numeric(ss$max_norm %||% 0.5)
  )
}

# Apply the deterministic caveats/veto pass to a scored gene matrix (post
# compute_composite, pre rank_genes). Always emits two columns so downstream
# report/CSV/ranking is uniform:
#   vetoed  - logical, TRUE if the gene is forced to the bottom
#   caveats - list-col of character reasons (the veto reason is included here)
# A caveat multiplies the composite by its penalty; a veto leaves the composite
# untouched (transparent) and is handled by rank_genes, which sinks vetoed genes.
# `enabled = FALSE` (or a disabled rubric) adds the empty columns and does nothing
# else, so callers can turn the stage off without changing the result shape.
apply_caveats <- function(
  genes,
  registry,
  context = list(),
  rubric = NULL,
  enabled = TRUE
) {
  n <- nrow(genes)
  genes$vetoed <- rep(FALSE, n)
  genes$caveats <- replicate(n, character(0), simplify = FALSE)
  if (n == 0) {
    return(genes)
  }

  cfg <- caveat_config(rubric)
  if (!isTRUE(enabled) || !isTRUE(cfg$enabled)) {
    return(genes)
  }

  # FLAGS set = universal (rubric) + disease-context priors, case-insensitive.
  prior_flags <- toupper(as.character(
    pluck_at(context, "priors", "flags_genes") %||% character()
  ))
  flags <- unique(c(cfg$flags_genes, prior_flags))

  keys <- vapply(registry, function(s) s$key, character(1))
  roles <- vapply(registry, function(s) s$role %||% "evidence", character(1))
  labels <- vapply(registry, function(s) s$label %||% s$key, character(1))
  ev_keys <- keys[roles == "evidence"]

  reasons <- vector("list", n)
  vetoed <- rep(FALSE, n)
  penalty <- rep(1, n)

  for (i in seq_len(n)) {
    r <- character(0)
    sym <- toupper(genes$symbol[i])

    # VETO: recurrent-artifact FLAGS gene.
    if (sym %in% flags) {
      vetoed[i] <- TRUE
      r <- c(
        r,
        "Recurrent sequencing-artifact (FLAGS) gene - vetoed to the bottom."
      )
    }

    # CAVEAT: supported only by a single, weak evidence source.
    n_ev <- if ("n_evidence_present" %in% names(genes)) {
      genes$n_evidence_present[i]
    } else {
      NA_integer_
    }
    if (!is.na(n_ev) && n_ev == 1L && length(ev_keys) > 0) {
      present <- vapply(
        ev_keys,
        function(k) {
          pcol <- paste0(k, "_present")
          pcol %in% names(genes) && isTRUE(genes[[pcol]][i])
        },
        logical(1)
      )
      if (any(present)) {
        k <- ev_keys[which(present)[1]]
        ncol <- paste0(k, "_n")
        norm_v <- if (ncol %in% names(genes)) {
          as.numeric(genes[[ncol]][i])
        } else {
          NA_real_
        }
        if (!is.na(norm_v) && norm_v < cfg$single_max_norm) {
          penalty[i] <- penalty[i] * cfg$single_penalty
          lbl <- labels[match(k, keys)]
          r <- c(
            r,
            sprintf(
              "Supported only by a single weak source (%s) - down-weighted.",
              lbl
            )
          )
        }
      }
    }

    reasons[[i]] <- r
  }

  genes$vetoed <- vetoed
  genes$caveats <- reasons
  genes$composite <- genes$composite * penalty
  genes
}

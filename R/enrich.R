# Gene-list enrichment: pull a ranking signal from each source for every gene,
# merge and dedupe by canonical gene id, and shape the tidy + wide tables the
# ranking and UI consume. Deterministic and gene-only (no disease term, no LLM);
# the free-text study description is reserved for the later agent stage.
#
# A SIGNAL is one source's contribution, defined once in the registry:
#   candid_signal(key, label, source, extractor, normalize, weight, direction,
#                 role, needs)
# `role` is "evidence" (counts toward breadth) or "annotation" (nudges but does
# not gate); `needs` is "gene" (per-gene extractor) or "disease" (a seeder, run
# before this step). Adding a source = one candid_signal() here plus its
# R/tools/ client. Each extractor returns a raw number + grounded evidence rows.

# --- Signal registry --------------------------------------------------------

candid_signal <- function(
  key,
  label,
  source,
  extractor,
  normalize,
  weight = 1,
  direction = "higher_better",
  role = "evidence",
  needs = "gene"
) {
  list(
    key = key,
    label = label,
    source = source,
    extractor = extractor,
    normalize = normalize,
    weight = weight,
    direction = direction,
    role = role,
    needs = needs
  )
}

# The active signal registry, wired from the rubric (weights + normalization
# midpoints). Registry order is the column order in the results table.
candid_signal_registry <- function(rubric = load_rubric()) {
  w <- rubric$weights %||% list()
  m <- rubric$midpoints %||% list()
  list(
    candid_signal(
      "ot_assoc",
      "Open Targets association",
      "Open Targets Platform",
      extractor = extract_ot_assoc,
      normalize = normalize_identity,
      weight = w$ot_assoc %||% 1,
      role = "evidence"
    ),
    candid_signal(
      "pmc_hits",
      "Europe PMC mentions",
      "Europe PMC",
      extractor = extract_pmc_hits,
      normalize = normalize_log_saturating(m$pmc_hits %||% 50),
      weight = w$pmc_hits %||% 0.5,
      role = "evidence"
    ),
    candid_signal(
      "clinvar_path",
      "ClinVar pathogenic variants",
      "ClinVar",
      extractor = extract_clinvar_path,
      normalize = normalize_saturating(m$clinvar_path %||% 5),
      weight = w$clinvar_path %||% 1,
      role = "evidence"
    ),
    candid_signal(
      "dgidb",
      "DGIdb drug interactions",
      "DGIdb",
      extractor = extract_dgidb,
      normalize = normalize_log_saturating(m$dgidb %||% 5),
      weight = w$dgidb %||% 0.5,
      role = "evidence"
    ),
    candid_signal(
      "gnomad_loeuf",
      "gnomAD LOEUF constraint",
      "gnomAD",
      extractor = extract_gnomad_loeuf,
      normalize = normalize_saturating_desc(m$gnomad_loeuf %||% 0.35),
      weight = w$gnomad_loeuf %||% 0.75,
      direction = "lower_better",
      role = "annotation"
    ),
    candid_signal(
      "pharos_tdl",
      "Pharos target dev. level",
      "Pharos",
      extractor = extract_pharos_tdl,
      normalize = normalize_identity,
      weight = w$pharos_tdl %||% 0.5,
      role = "annotation"
    )
  )
}

# A compact registry description for the UI legend / result object.
registry_summary <- function(registry) {
  tibble::tibble(
    key = vapply(registry, function(s) s$key, character(1)),
    label = vapply(registry, function(s) s$label, character(1)),
    source = vapply(registry, function(s) s$source, character(1)),
    weight = vapply(registry, function(s) s$weight, numeric(1)),
    role = vapply(registry, function(s) s$role %||% "evidence", character(1)),
    direction = vapply(
      registry,
      function(s) s$direction %||% "higher_better",
      character(1)
    )
  )
}

# --- Extractors -------------------------------------------------------------
# extractor(resolved, context) -> list(ok, raw, source_id, source_url, evidence)
# `resolved` is a list with $gene_id (canonical Ensembl id), $symbol, $entrez.
# `context` is a list carrying run-wide state; `context$disease` (a resolved
# disease, or NULL) lets a gene-keyed extractor run a disease-aware query. All
# PR1 extractors are gene-only and ignore `context`; PR2 wires the disease path.

# No signal for this gene from this source (absent or lookup failed).
signal_miss <- function() {
  list(
    ok = FALSE,
    raw = NA_real_,
    source_id = "",
    source_url = "",
    evidence = empty_evidence_long()
  )
}

# Open Targets: max disease-association score (0-1); evidence = the disease rows.
extract_ot_assoc <- function(resolved, context = list()) {
  a <- gene_disease_assoc(resolved$gene_id)
  if (!isTRUE(a$ok) || nrow(a$evidence) == 0) {
    return(signal_miss())
  }
  ev <- a$evidence
  top <- ev[which.max(ev$score), ]
  list(
    ok = TRUE,
    raw = max(ev$score, na.rm = TRUE),
    source_id = top$source_id,
    source_url = top$source_url,
    evidence = evidence_long_rows(
      resolved$gene_id,
      "ot_assoc",
      domain = "pathway-disease",
      title = ev$disease,
      detail = sprintf("association score %.2f", ev$score),
      score = ev$score,
      source_id = ev$source_id,
      source_url = ev$source_url
    )
  )
}

# Europe PMC: total gene-mention count; evidence = a summary row linking the query.
extract_pmc_hits <- function(resolved, context = list()) {
  q <- sprintf('"%s"', resolved$symbol)
  r <- europepmc_count(q)
  if (!isTRUE(r$ok)) {
    return(signal_miss())
  }
  list(
    ok = TRUE,
    raw = r$count,
    source_id = r$source_id,
    source_url = r$source_url,
    evidence = evidence_long_rows(
      resolved$gene_id,
      "pmc_hits",
      domain = "literature",
      title = sprintf("%d Europe PMC mentions of %s", r$count, resolved$symbol),
      detail = sprintf("query %s", q),
      score = NA_real_,
      source_id = r$source_id,
      source_url = r$source_url
    )
  )
}

# ClinVar: count of pathogenic / likely-pathogenic variants; evidence = summary row.
extract_clinvar_path <- function(resolved, context = list()) {
  r <- clinvar_gene_pathogenic_count(resolved$symbol)
  if (!isTRUE(r$ok)) {
    return(signal_miss())
  }
  list(
    ok = TRUE,
    raw = r$count,
    source_id = r$source_id,
    source_url = r$source_url,
    evidence = evidence_long_rows(
      resolved$gene_id,
      "clinvar_path",
      domain = "variant-effect",
      title = sprintf(
        "%d pathogenic / likely-pathogenic ClinVar variants",
        r$count
      ),
      detail = "germline classification",
      score = NA_real_,
      source_id = r$source_id,
      source_url = r$source_url
    )
  )
}

# DGIdb: number of curated drug-gene interactions (a druggability / actionability
# signal). A gene present in DGIdb with 0 interactions is a real 0; a gene absent
# from DGIdb is a miss.
extract_dgidb <- function(resolved, context = list()) {
  r <- dgidb_gene_interactions(resolved$symbol)
  if (!isTRUE(r$ok)) {
    return(signal_miss())
  }
  list(
    ok = TRUE,
    raw = r$count,
    source_id = r$source_id,
    source_url = r$source_url,
    evidence = evidence_long_rows(
      resolved$gene_id,
      "dgidb",
      domain = "druggability",
      title = sprintf("%d drug-gene interactions (DGIdb)", r$count),
      detail = "curated across DGIdb interaction sources",
      score = NA_real_,
      source_id = r$source_id,
      source_url = r$source_url
    )
  )
}

# gnomAD: LOEUF loss-of-function constraint (lower = more constrained = more
# likely essential). Annotation signal, normalized descending so low LOEUF -> high
# score. Absent constraint record is a miss.
extract_gnomad_loeuf <- function(resolved, context = list()) {
  r <- gnomad_loeuf(resolved$symbol)
  if (!isTRUE(r$ok) || is_blank(r$loeuf)) {
    return(signal_miss())
  }
  detail <- if (!is_blank(r$pli)) {
    sprintf("pLI %.2f", r$pli)
  } else {
    "loss-of-function constraint"
  }
  list(
    ok = TRUE,
    raw = r$loeuf,
    source_id = r$source_id,
    source_url = r$source_url,
    evidence = evidence_long_rows(
      resolved$gene_id,
      "gnomad_loeuf",
      domain = "constraint",
      title = sprintf(
        "gnomAD LOEUF %.2f (lower = more LoF-constrained)",
        r$loeuf
      ),
      detail = detail,
      score = NA_real_,
      source_id = r$source_id,
      source_url = r$source_url
    )
  )
}

# Pharos: target development level (Tclin/Tchem/Tbio/Tdark) mapped to a 0-1
# druggability/actionability score. Annotation signal.
extract_pharos_tdl <- function(resolved, context = list()) {
  r <- pharos_tdl(resolved$symbol)
  if (!isTRUE(r$ok) || is_blank(r$score)) {
    return(signal_miss())
  }
  list(
    ok = TRUE,
    raw = r$score,
    source_id = r$source_id,
    source_url = r$source_url,
    evidence = evidence_long_rows(
      resolved$gene_id,
      "pharos_tdl",
      domain = "druggability",
      title = sprintf("Pharos target development level: %s", r$tdl),
      detail = sprintf("TDL druggability score %.2f", r$score),
      score = NA_real_,
      source_id = r$source_id,
      source_url = r$source_url
    )
  )
}

# --- Flatten, resolve, dedupe -----------------------------------------------

# Union many named gene lists into unique tokens, remembering which list(s) each
# came from. `lists` is a named list of character vectors. Blank lines and lines
# starting with '#' are dropped. Returns tibble(token, input_lists = list-col).
flatten_gene_lists <- function(lists) {
  membership <- list()
  order <- character()
  for (nm in names(lists)) {
    toks <- trimws(as.character(lists[[nm]]))
    toks <- toks[nzchar(toks) & !startsWith(toks, "#")]
    for (t in toks) {
      key <- toupper(t)
      if (is.null(membership[[key]])) {
        membership[[key]] <- list(token = t, lists = character())
        order <- c(order, key)
      }
      membership[[key]]$lists <- union(membership[[key]]$lists, nm)
    }
  }
  if (length(order) == 0) {
    return(tibble::tibble(token = character(), input_lists = list()))
  }
  tibble::tibble(
    token = vapply(
      order,
      function(k) membership[[k]]$token,
      character(1),
      USE.NAMES = FALSE
    ),
    input_lists = unname(lapply(order, function(k) sort(membership[[k]]$lists)))
  )
}

# Resolve every token to a canonical gene id (MyGene ensembl_gene) and dedupe by
# it, so aliases collapse to one gene. `resolver` is injectable for offline tests.
# Unresolved tokens keep a synthetic id and resolved = FALSE (shown, not dropped).
resolve_genes <- function(flat, resolver = resolve_symbol) {
  if (nrow(flat) == 0) {
    return(empty_resolved())
  }
  rows <- lapply(seq_len(nrow(flat)), function(i) {
    token <- flat$token[i]
    r <- resolver(token)
    if (isTRUE(r$ok) && !is_blank(r$ensembl_gene)) {
      list(
        gene_id = r$ensembl_gene,
        symbol = r$symbol %||% token,
        entrez = as.character(r$entrez %||% NA),
        resolved = TRUE,
        token = token,
        input_lists = flat$input_lists[[i]]
      )
    } else {
      list(
        gene_id = paste0("UNRESOLVED:", toupper(token)),
        symbol = token,
        entrez = NA_character_,
        resolved = FALSE,
        token = token,
        input_lists = flat$input_lists[[i]]
      )
    }
  })
  merge_resolved(rows)
}

# Collapse resolved rows by gene_id, aggregating input symbols and list membership.
merge_resolved <- function(rows) {
  by_id <- list()
  order <- character()
  for (r in rows) {
    id <- r$gene_id
    if (is.null(by_id[[id]])) {
      by_id[[id]] <- list(
        gene_id = id,
        symbol = r$symbol,
        entrez = r$entrez,
        resolved = r$resolved,
        input_symbols = character(),
        input_lists = character()
      )
      order <- c(order, id)
    }
    by_id[[id]]$input_symbols <- union(by_id[[id]]$input_symbols, r$token)
    by_id[[id]]$input_lists <- union(by_id[[id]]$input_lists, r$input_lists)
  }
  pull <- function(f) vapply(order, f, character(1), USE.NAMES = FALSE)
  tibble::tibble(
    gene_id = pull(function(k) by_id[[k]]$gene_id),
    symbol = pull(function(k) by_id[[k]]$symbol),
    entrez = pull(function(k) as.character(by_id[[k]]$entrez)),
    resolved = vapply(
      order,
      function(k) by_id[[k]]$resolved,
      logical(1),
      USE.NAMES = FALSE
    ),
    input_symbols = unname(lapply(order, function(k) {
      sort(by_id[[k]]$input_symbols)
    })),
    input_lists = unname(lapply(order, function(k) {
      sort(by_id[[k]]$input_lists)
    }))
  )
}

empty_resolved <- function() {
  tibble::tibble(
    gene_id = character(),
    symbol = character(),
    entrez = character(),
    resolved = logical(),
    input_symbols = list(),
    input_lists = list()
  )
}

# --- Enrich + assemble ------------------------------------------------------

empty_signals_long <- function() {
  tibble::tibble(
    gene_id = character(),
    symbol = character(),
    signal_key = character(),
    label = character(),
    raw = numeric(),
    normalized = numeric(),
    present = logical(),
    source_id = character(),
    source_url = character()
  )
}

# Run every gene-keyed registry signal for every resolved gene. Returns the tidy
# signals table (one row per gene x signal) and grounded evidence for drill-down.
# Disease-keyed (`needs = "disease"`) signals are seeders handled before this
# step; they are skipped here. `context` is passed to each extractor.
enrich_genes <- function(
  resolved,
  registry = candid_signal_registry(),
  context = list()
) {
  gene_signals <- Filter(
    function(s) identical(s$needs %||% "gene", "gene"),
    registry
  )
  signals <- list()
  evidence <- list()
  for (i in seq_len(nrow(resolved))) {
    gene <- list(
      gene_id = resolved$gene_id[i],
      symbol = resolved$symbol[i],
      entrez = resolved$entrez[i],
      resolved = resolved$resolved[i]
    )
    for (sig in gene_signals) {
      res <- if (isTRUE(gene$resolved)) {
        tryCatch(sig$extractor(gene, context), error = function(e) {
          signal_miss()
        })
      } else {
        signal_miss()
      }
      raw <- as.numeric(res$raw)
      signals[[length(signals) + 1]] <- tibble::tibble(
        gene_id = gene$gene_id,
        symbol = gene$symbol,
        signal_key = sig$key,
        label = sig$label,
        raw = raw,
        normalized = as.numeric(sig$normalize(raw)),
        present = isTRUE(res$ok) && !is.na(raw),
        source_id = res$source_id %||% "",
        source_url = res$source_url %||% ""
      )
      if (!is.null(res$evidence) && nrow(res$evidence) > 0) {
        evidence[[length(evidence) + 1]] <- res$evidence
      }
    }
  }
  list(
    signals_long = if (length(signals)) {
      dplyr::bind_rows(signals)
    } else {
      empty_signals_long()
    },
    evidence_long = if (length(evidence)) {
      dplyr::bind_rows(evidence)
    } else {
      empty_evidence_long()
    }
  )
}

# Pivot the tidy signals to one row per gene (raw <key> + normalized <key>_n
# columns), joined with resolved-gene metadata and a coverage count.
assemble_matrix <- function(
  signals_long,
  resolved,
  registry = candid_signal_registry()
) {
  keys <- vapply(registry, function(s) s$key, character(1))
  roles <- vapply(registry, function(s) s$role %||% "evidence", character(1))
  genes <- resolved$gene_id
  # Pre-extract: tibble() data-masks columns as it builds them, so a column named
  # `resolved` would shadow the `resolved` argument for later columns.
  symbols <- resolved$symbol
  resolved_flag <- resolved$resolved
  input_lists <- resolved$input_lists
  mat <- tibble::tibble(
    gene_id = genes,
    symbol = symbols,
    resolved = resolved_flag,
    input_lists = input_lists
  )
  for (k in keys) {
    sub <- signals_long[signals_long$signal_key == k, , drop = FALSE]
    raw_by <- stats::setNames(sub$raw, sub$gene_id)
    norm_by <- stats::setNames(sub$normalized, sub$gene_id)
    pres_by <- stats::setNames(sub$present, sub$gene_id)
    mat[[k]] <- as.numeric(raw_by[genes])
    mat[[paste0(k, "_n")]] <- as.numeric(norm_by[genes])
    p <- pres_by[genes]
    p[is.na(p)] <- FALSE
    mat[[paste0(k, "_present")]] <- as.logical(p)
  }
  # Coverage counts: all present signals (display) and evidence-only present
  # signals (the breadth measure the composite's coverage bonus uses).
  ev_keys <- keys[roles == "evidence"]
  count_present <- function(g, which_keys) {
    sum(signals_long$present[
      signals_long$gene_id == g & signals_long$signal_key %in% which_keys
    ])
  }
  mat$n_sources_present <- vapply(
    genes,
    function(g) count_present(g, keys),
    integer(1),
    USE.NAMES = FALSE
  )
  mat$n_evidence_present <- vapply(
    genes,
    function(g) count_present(g, ev_keys),
    integer(1),
    USE.NAMES = FALSE
  )
  mat
}

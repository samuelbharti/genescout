# Input parsing. Turns an uploaded table or pasted text into a normalized
# candidate tibble with columns: candidate, type, gene, variant, note.
# Pure and offline (no network, no LLM) so it is safe to run on every input.

# A candidate row is one of: a gene symbol, or a variant (HGVS / rsID / g.).
# `type` is a coarse guess used only to route retrieval, never as a claim.
guess_type <- function(x) {
  ifelse(
    grepl("^rs[0-9]+$", x) |
      grepl("[:.]|>|del|ins|dup", x, ignore.case = TRUE) |
      grepl("^[0-9XYM]+-[0-9]+-[ACGT]+-[ACGT]+$", x, ignore.case = TRUE),
    "variant",
    "gene"
  )
}

# Parse pasted text: one candidate per line, blank lines and comments dropped.
parse_candidate_lines <- function(text) {
  lines <- trimws(strsplit(text, "\r?\n")[[1]])
  lines <- lines[nzchar(lines) & !startsWith(lines, "#")]
  if (length(lines) == 0) {
    stop("No candidates found in pasted text.", call. = FALSE)
  }
  type <- guess_type(lines)
  tibble::tibble(
    candidate = lines,
    type = type,
    gene = ifelse(type == "gene", lines, NA_character_),
    variant = ifelse(type == "variant", lines, NA_character_),
    note = NA_character_
  )
}

# Parse an uploaded table. Accepts TSV/CSV; a `gene`/`candidate`/`symbol` column
# is required. Extra columns are preserved as-is on the returned tibble.
read_candidate_table <- function(path) {
  sep <- if (grepl("\\.csv$", path, ignore.case = TRUE)) "," else "\t"
  df <- utils::read.delim(
    path,
    sep = sep,
    header = TRUE,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  names(df) <- tolower(names(df))
  key <- intersect(c("candidate", "gene", "symbol"), names(df))[1]
  if (is.na(key)) {
    stop(
      "Table needs a 'candidate', 'gene', or 'symbol' column.",
      call. = FALSE
    )
  }
  candidate <- as.character(df[[key]])
  type <- if ("type" %in% names(df)) {
    as.character(df$type)
  } else {
    guess_type(candidate)
  }
  tibble::tibble(
    candidate = candidate,
    type = type,
    gene = if ("gene" %in% names(df)) as.character(df$gene) else candidate,
    variant = if ("variant" %in% names(df)) {
      as.character(df$variant)
    } else {
      NA_character_
    },
    note = if ("note" %in% names(df)) as.character(df$note) else NA_character_
  )
}

# --- Bundled examples -------------------------------------------------------
# Public/synthetic example candidate lists in data/examples/, used by the UI's
# "load example" button. `dir` is injectable so the helper is testable offline.

# Path to a bundled example table (e.g. "nf1_candidates" -> the NF1 gene list).
example_path <- function(name, dir = file.path("data", "examples")) {
  file.path(dir, paste0(name, ".tsv"))
}

# Read a bundled example and return its candidates as newline-joined text,
# ready to pre-fill the paste box. The parse path then handles it like any paste.
example_text <- function(name, dir = file.path("data", "examples")) {
  df <- read_candidate_table(example_path(name, dir))
  paste(df$candidate, collapse = "\n")
}

# Assemble the named gene lists the pipeline consumes from the paste box and an
# optional uploaded table. Each source becomes one named list, so a gene's origin
# is retained through de-duplication. Returns list() when nothing was provided.
collect_gene_lists <- function(pasted, file_path = NULL) {
  lists <- list()
  if (!is.null(pasted) && nzchar(trimws(pasted %||% ""))) {
    lists[["pasted"]] <- strsplit(pasted, "\r?\n")[[1]]
  }
  if (!is.null(file_path) && nzchar(file_path)) {
    tbl <- tryCatch(read_candidate_table(file_path), error = function(e) NULL)
    if (!is.null(tbl)) {
      lists[["uploaded"]] <- as.character(tbl$candidate)
    }
  }
  lists
}

# --- Multi-source candidate model -------------------------------------------
# A `candidate_set` is CANDID's canonical, UI-agnostic input: an ordered list of
# `candid_source` records, each a named/typed bag of raw gene tokens. The bare
# named list of character vectors the pipeline used before is a strict subset
# (one source per name), so every existing caller keeps working through
# as_candidate_set() / as_gene_lists(). Everything is a plain list, so a set
# round-trips through jsonlite for a non-R frontend (Shiny-Python, React, CLI).

# Slug a human label into an id-safe token (lowercase, non-alnum -> '-'). Colons
# are stripped, so a user source id can never collide with a reserved 'seed:' id.
slugify <- function(x) {
  s <- tolower(trimws(as.character(x %||% "")))
  s <- gsub("[^a-z0-9]+", "-", s)
  s <- gsub("(^-+)|(-+$)", "", s)
  if (nzchar(s)) s else "source"
}

# Suggested (free-text) source types for the UI datalist / CLI hint. `type` stays
# free text and is never treated as a claim - this is only a vocabulary.
candid_source_types <- function() {
  c(
    "unspecified",
    "wes",
    "wgs",
    "rnaseq_deg",
    "atacseq",
    "chipseq",
    "crispr",
    "proteomics",
    "gwas",
    "panel",
    "curated",
    "literature",
    "disease_seed"
  )
}

# One tagged source of candidate genes. `genes` are raw tokens (symbols or free
# text; cleaned later by the flatten step). `seeded = TRUE` marks a source the
# engine injected (e.g. a disease-discovery universe) so it is excluded from
# cross-source corroboration. Classed for robust dispatch; still a plain list.
candid_source <- function(
  genes,
  label = NULL,
  type = "unspecified",
  note = NULL,
  id = NULL,
  seeded = FALSE
) {
  label <- label %||% "input"
  structure(
    list(
      id = as.character(id %||% slugify(label)),
      label = as.character(label),
      type = as.character(type %||% "unspecified"),
      note = if (is.null(note)) NA_character_ else as.character(note),
      seeded = isTRUE(seeded),
      genes = as.character(genes)
    ),
    class = "candid_source"
  )
}

# Make source ids unique within a set (a collision gets a '-2', '-3' suffix) so
# per-source provenance never merges two distinct sources downstream.
dedupe_source_ids <- function(sources) {
  seen <- character()
  for (i in seq_along(sources)) {
    id <- sources[[i]]$id %||% slugify(sources[[i]]$label %||% "source")
    base <- id
    k <- 2L
    while (id %in% seen) {
      id <- paste0(base, "-", k)
      k <- k + 1L
    }
    seen <- c(seen, id)
    sources[[i]]$id <- id
  }
  sources
}

# The low-level constructor: an ordered, classed collection of candid_source
# records (ids made unique). Order is the display / tie-break order.
new_candidate_set <- function(sources = list()) {
  structure(dedupe_source_ids(sources), class = "candid_candidate_set")
}

# Convenience constructor: candidate_set(src1, src2, ...) or candidate_set(<list
# of sources>). Every frontend builds its input through this.
candidate_set <- function(...) {
  sources <- list(...)
  if (
    length(sources) == 1L &&
      is.list(sources[[1]]) &&
      !inherits(sources[[1]], "candid_source")
  ) {
    sources <- sources[[1]]
  }
  new_candidate_set(sources)
}

# Coerce assorted inputs into a candidate_set. Supersedes as_gene_lists(): passes
# a candidate_set through; wraps a single candid_source; a bare character vector
# -> one source "input"; a gene/candidate/symbol data frame -> one source; and a
# NAMED list of character vectors (the pipeline's old shape) -> one source per
# name with id = label = name, so downstream provenance (input_lists) stays
# byte-identical. Dispatch on the classes FIRST (a candidate_set is itself a
# list, so a bare is.list() branch would mis-handle it).
as_candidate_set <- function(x) {
  if (inherits(x, "candid_candidate_set")) {
    return(x)
  }
  if (inherits(x, "candid_source")) {
    return(new_candidate_set(list(x)))
  }
  if (is.data.frame(x)) {
    col <- intersect(c("gene", "candidate", "symbol"), names(x))[1]
    genes <- if (!is.na(col)) as.character(x[[col]]) else character()
    return(new_candidate_set(list(candid_source(genes, label = "input"))))
  }
  if (is.character(x)) {
    return(new_candidate_set(list(candid_source(x, label = "input"))))
  }
  if (is.list(x)) {
    nms <- names(x)
    if (is.null(nms)) {
      nms <- rep("", length(x))
    }
    srcs <- lapply(seq_along(x), function(i) {
      nm <- nms[i]
      if (!nzchar(nm %||% "")) {
        nm <- if (length(x) == 1L) "input" else paste0("source_", i)
      }
      candid_source(x[[i]], label = nm, id = nm)
    })
    return(new_candidate_set(srcs))
  }
  new_candidate_set(list())
}

# Down-convert a candidate_set to the named-list-of-character-vectors shape older
# callers expect (one entry per source label). The back-compat inverse of the
# named-list branch of as_candidate_set().
candidate_set_to_named_lists <- function(cs) {
  cs <- as_candidate_set(cs)
  out <- list()
  for (src in cs) {
    out[[src$label]] <- src$genes
  }
  out
}

# Convert a candidate_set to a plain, unclassed list-of-lists ready for jsonlite
# (a non-R frontend / the plumber API). `note` is omitted when absent and `genes`
# is kept an array even at length 1. The inverse is candidate_set_from_list().
candidate_set_to_list <- function(cs) {
  cs <- as_candidate_set(cs)
  lapply(cs, function(s) {
    out <- list(
      id = s$id,
      label = s$label,
      type = s$type,
      seeded = s$seeded,
      genes = I(as.character(s$genes))
    )
    if (!is.na(s$note)) {
      out$note <- s$note
    }
    out
  })
}

# Rebuild a candidate_set from the plain list a frontend/API posts (the parsed
# JSON, with simplifyVector = FALSE). The inverse of candidate_set_to_list().
candidate_set_from_list <- function(x) {
  srcs <- lapply(x, function(s) {
    candid_source(
      genes = unlist(s$genes, use.names = FALSE) %||% character(),
      label = s$label,
      type = s$type %||% "unspecified",
      note = s$note,
      id = s$id,
      seeded = isTRUE(s$seeded)
    )
  })
  new_candidate_set(srcs)
}

# Build a candidate_set from UI/CLI source specs. Each spec is a list with a
# `name` (label), optional `type`, and one of: `genes` (a vector), `text`
# (pasted, newline-separated), or `file` (a table path). Empty sources are
# dropped so a blank "+ add a source" row never becomes a phantom source. This is
# the single constructor Shiny, the CLI, and the API all call.
collect_candidate_set <- function(specs) {
  srcs <- list()
  for (i in seq_along(specs)) {
    spec <- specs[[i]]
    genes <- character()
    if (!is.null(spec$genes)) {
      genes <- as.character(spec$genes)
    } else if (!is.null(spec$text) && nzchar(trimws(spec$text %||% ""))) {
      genes <- strsplit(spec$text, "\r?\n")[[1]]
    } else if (!is.null(spec$file) && nzchar(spec$file)) {
      tbl <- tryCatch(read_candidate_table(spec$file), error = function(e) NULL)
      if (!is.null(tbl)) {
        genes <- as.character(tbl$candidate)
      }
    }
    genes <- genes[!is.na(genes) & nzchar(trimws(genes))]
    if (length(genes) == 0L) {
      next
    }
    label <- spec$name %||% spec$label %||% paste0("source_", i)
    srcs[[length(srcs) + 1L]] <- candid_source(
      genes,
      label = label,
      type = spec$type %||% "unspecified"
    )
  }
  new_candidate_set(srcs)
}

# Dispatch on an input source list(file = <path|NULL>, text = <chr|NULL>).
parse_candidates <- function(source) {
  if (!is.null(source$file) && nzchar(source$file)) {
    return(read_candidate_table(source$file))
  }
  if (!is.null(source$text) && nzchar(trimws(source$text %||% ""))) {
    return(parse_candidate_lines(source$text))
  }
  stop(
    "No candidates provided - upload a table or paste gene symbols.",
    call. = FALSE
  )
}

# Null/empty-coalescing helper used above.
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x # nolint: object_name_linter.

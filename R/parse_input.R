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

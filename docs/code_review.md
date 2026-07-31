# Code review, v0.1.0

A full review of the repository as of the 0.1.0 release (commit `cdd74a6`). Every finding
below was verified against the source; each carries a `file:line` and a note on why it
matters.

The review is organized by severity. Findings marked **[fixed]** were addressed in the
follow-up PRs; the rest are recorded here as known issues with a recommended direction.

## Summary

The codebase is in good shape. The deterministic spine is coherent, comments explain *why*
rather than *what*, and several of the project's own non-negotiables are genuinely upheld
rather than merely asserted.

Verified strengths:

- **Test assertions are strong.** 386 `test_that()` blocks, ~1,118 expectations, zero
  `expect_true(TRUE)`, zero `expect_no_error`. Tests assert exact counts, exact `source_id`
  strings, and de-duplication invariants. `tests/testthat/test-dgidb.R:11-20` distinguishes a
  real zero from an absent gene, which is a distinction many suites miss.
- **`docs/data_sources.md` covers all 24 clients.** Non-negotiable #6 is being honoured.
- **`renv.lock` and `manifest.json` are in exact sync**: 94 packages each, identical sets,
  zero version mismatches, both on R 4.6.1, matching `Dockerfile:3`.
- **No ellmer in `R/tools/`.** All 24 files are plain, testable R. The rule holds.
- **No clinical-interpretation creep.** Prompts and schemas forbid clinical calls
  (`R/specialists.R:158-159`, `:490-492`), and no ACMG language appears anywhere.
- **Grounding is enforced structurally where it counts most.** `clean_specialist_result()`
  (`R/specialists.R:198-238`) intersects model-cited ids against the gene's real evidence ids
  and drops any finding left ungrounded. A fabricated citation cannot survive.
- **`air format --check` is genuinely enforced in CI** (`.github/workflows/ci.yaml:20-26`).
- **`app.R` is a correct shim**, not a duplicate app definition, and says why it exists.
- **Accessibility leads the sibling family** (52 aria/role/sr-only usages against 0-10 in
  comparable apps).

Problems cluster in three areas: a gap between what `CLAUDE.md` claims and what the code
does; failures and secrets leaking or being swallowed at stage boundaries; and two
reactivity bugs that destroy paid-for LLM output.

## High severity

### 1. The citation gate does not gate the score **[fixed]**

`R/orchestrate.R:218-219`. `validate_evidence()` filters `evidence_long`, but
`assemble_matrix()` is fed the **ungated** `signals_long`. Nothing validated that a *signal*
row carried a `source_id`.

An extractor returning `ok = TRUE, raw = <number>, source_id = ""` moved the composite,
changed the rank, and printed a number in the ranked table, while its evidence row was
silently dropped as ungrounded. The gate protected the drill-down, not the ranking. This is
the finding that most directly contradicts non-negotiable #2.

Reachable in practice: `R/enrich.R:1867` defaults `source_id` to `""`, and `present` at
`:1866` never consults it. See finding 2 for a concrete path.

### 2. `extract_ot_assoc` can emit `-Inf` with an empty `source_id` **[fixed]**

`R/enrich.R:658-663`. If every `ev$score` is NA (`opentargets_parse_rows` emits `NA_real_`
for a missing `score` field, `R/tools/opentargets.R:127-131`), then `which.max()` returns
`integer(0)`, `top` is a 0-row tibble, and the result is `raw = -Inf`, `source_id =
character(0)` coerced to `""`, with `present = TRUE` because `!is.na(-Inf)` is TRUE.

A gene scored as "Open Targets present", contributing to `n_evidence_present`, with no
citation. Detail strings also render as `"association score NA"` (`R/enrich.R:670`).

### 3. One LLM error path leaks the BYOK key to the browser **[fixed]**

`modules/mod_review.R:314-320` passed raw `conditionMessage(e)` to `showNotification`. Every
comparable path redacts: `modules/mod_results.R:256`, `:344`, and `modules/mod_chat.R:101`,
`:157`, `:168` all wrap the message in `genescout_redact_secret(..., cfg$api_key)`. This was
the only LLM-call error path that did not, and it is on the BYOK path where the user has
pasted their own key.

Compounding it, the three LLM stages catch provider errors internally and stash the raw
message (`R/curate.R:390`, `R/specialists.R:439`, `R/input_agent.R:432`), so the outer
redacting handler never fired for those paths. Provider SDKs routinely echo the request,
including an `Authorization` prefix, into error text.

### 4. The NCBI API key entered the cache key and the request URL **[fixed]**

`R/tools/clinvar.R:23-26` and `:81-84` inject `api_key` into `query`, which is passed
straight to `genescout_cache_key("GET", base_url, path, query)` at `R/http.R:125`.

This contradicts the policy the HTTP wrapper states in its own comment at `R/http.R:109-112`:
secrets "are DELIBERATELY excluded from the cache key ... the secret must never enter the
hashed key". `req_headers(.redact=)` does not cover query parameters, so the key also
appeared in the outbound URL and in any verbose or proxy log.

Related: the `clinvar_path` signal (`R/enrich.R:217-226`) declared no `auth` or `key_env`, so
`genescout_catalog_json()` reported `auth = "none"` while the client consumed `NCBI_API_KEY`.

### 5. Moving a weight slider destroyed paid-for AI output **[fixed]**

`result` is a `reactive()` depending on `inputs$weights()` (`modules/mod_review.R:351-362`),
and `modules/mod_results.R:236` and `:314` reset `curated` and `specialists` on every
`result()` invalidation.

So: run a review, click "Curate with AI" and "Analyze with specialists" (two LLM round-trips,
real money), then nudge one weight slider. Both AI outputs are silently wiped and the
Plausibility column vanishes, with no notification explaining why.

The UI actively invites the action that destroys the output. `modules/mod_input.R:196-197`
reads: "Adjust how much each source counts; the table re-ranks instantly with no re-query."

The reset should key off the *enrichment*, not the *ranking*: re-ranking does not change the
underlying evidence the specialists read.

### 6. Outage is indistinguishable from absence

`R/enrich.R:1852-1854` maps any extractor exception to `signal_miss()`. No count, no message,
no `context` entry. There are no logging calls anywhere in `R/enrich.R`, `R/http.R`, or
`R/orchestrate.R`.

So "Open Targets was down for the entire run" and "this gene has no Open Targets association"
produce byte-identical output. The circuit breaker (`R/http.R:60-105`) makes it worse: after
3 transport failures a host is skipped for 120s, turning an outage into instant silent
misses. `genescout_provenance()` still lists the source as queried.

This contradicts non-negotiable #3 and the convention at `CLAUDE.md:94` that "all external
identifiers and versions are logged, not silently assumed".

A first increment (per-source failure counts surfaced in provenance and the context strip)
shipped in PR B. The fuller answer is `multi-variant-reviewer/R/status.R`'s 7-state envelope
(`ok / no_data / stale / rate_limited / timeout / skipped / error`), which is a direct
widening of this repo's 4-field contract and is recommended as follow-up work.

## Medium severity

### 7. `apply_input_validator` matched validator output positionally **[fixed]**

`R/input_agent.R:296-310` looped `for (k in seq_along(idx))` and read `checked[k, ]`,
assuming the validator returns exactly one row per input symbol in input order. If it
dedupes, filters, or reorders (a common shape for an ID-mapping API), symbol *k* received
gene *k*'s canonicalization, with reason text `"normalized X -> Y"` that looks authoritative.

`R/eval_checks.R` exists because a wrong-gene resolution slipped through once before. This is
the same bug class on a path the identity guard does not cover, since it runs pre-confirm.

### 8. The extractor `tryCatch` was scoped one line too narrowly **[fixed]**

`R/enrich.R:1851-1869`. The `tryCatch` covered only `sig$extractor(gene, context)`; the
`tibble::tibble(...)` construction at `:1859-1869` sat outside it. An extractor returning a
zero-length or length > 1 `raw`/`source_id` threw a "columns must have compatible sizes"
error that escaped `enrich_genes()`. In the parallel path that then errored the daemon task,
triggered a serial recompute with no guard (`R/parallel.R:184`), threw again, propagated to
`enrich_genes_dispatch` (`R/parallel.R:90-108`), and re-ran the *entire* serial enrichment
before dying, after paying for the network twice.

### 9. Specialist `strength` defaulted to `"moderate"` **[fixed]**

`R/specialists.R:202-205`. A missing, empty, or garbled `strength` from the model became
`"moderate"`, rendered as a confident blue badge (`R/report.R:461`). The safe default for an
unparseable confidence field is `"none"`. `clean_synthesis_result` (`R/specialists.R:576-578`)
gets the analogous case right by defaulting to `"uncertain"`.

### 10. The request side of all 24 clients is untested

`CLAUDE.md:52` and `:103` promise `httptest2` fixtures. `httptest2` appears in exactly one
place in the repo, `dev/init-renv.R:29`, in an install list. It is not in `DESCRIPTION`, not
in `renv.lock`, not in `manifest.json`, and is imported by zero tests. There is no mocking of
any kind: `grep` for `local_mocked_bindings|with_mocked_bindings|mockery|httptest2` across
`tests/` returns nothing.

What exists is two hand-rolled fixture readers (`tests/testthat/setup.R:8-16`) that feed saved
JSON straight into the parse functions. The parsers are well covered; the *requests* are not.
URL paths, query parameter names, GraphQL query bodies, headers, and pagination are all
unverified.

Concretely: change `aspect=biological_process` in `R/tools/quickgo.R` to a typo, or break a
GraphQL field name, and the suite stays green while the app silently returns misses for every
gene. For an app whose value proposition is grounded evidence from 24 third-party APIs, this
is the most consequential coverage gap.

Recommendation: adopt `httptest2` for real and record request fixtures, starting with the
GraphQL clients (Open Targets, gnomAD, CIViC, DGIdb, Pharos) where a silent field-name break
is both most likely and most damaging.

### 11. No Shiny module has any test

`grep -rl "testServer\|AppDriver\|shinytest2"` over `tests/` and `dev/` returns nothing. That
leaves 1,947 lines of module server logic untested (`modules/mod_input.R` 785,
`mod_review.R` 438, `mod_results.R` 358, `mod_keys.R` 189, `mod_chat.R` 177).

Findings 5 and 13 are pure-logic reactivity bugs that a five-line `testServer()` test would
have caught. PR C adds the first such tests. Six sibling projects have a `shinytest2` smoke
test; this repo has none, and that remains the single biggest testing hole.

### 12. There is no throttle, despite a comment claiming there is **[fixed]**

`R/parallel.R:28` states the daemon cap "pairs with the per-host throttle and circuit-breaker
in R/http.R". `grep -rn req_throttle R/` returned nothing. With 6 daemons hitting NCBI
E-utilities concurrently (`R/tools/clinvar.R`), a run exceeds NCBI's 3 req/s keyless limit
immediately and risks an IP block.

### 13. Stale selection after a re-run **[fixed]**

`modules/mod_results.R:174` reads `isolate(input$selected_symbol)`, which is set by JS
(`www/js/genescout.js:19`) and was never cleared between runs. Run A selects `TP53`; run B is
a different list without `TP53`. The table then highlights nothing
(`R/review_render.R:260`), while `output$detail_pane` falls back to `genes[1, ]`
(`mod_results.R:187-191`). Table and detail pane disagree about what is selected.

Related: `mod_results.R:187` had no `req(nrow(genes) > 0)` guard, so an empty result set
indexed `genes$symbol[1]` to `NA` and then `genes[1, ]` on an empty tibble.

### 14. `resolve_disease()` blocks the UI with no feedback **[fixed]**

`modules/mod_input.R:601-623` called `resolve_disease(term)` directly in an `observeEvent`
with no `withProgress()`, no spinner, and no button disable. Clicking "Find" froze the UI
with zero feedback until the Open Targets round-trip returned, up to 15s times 3 retries per
`R/http.R:118-119`. This is on the primary input path, so it is the most visible instance of
the broader blocking problem in finding 21.

### 15. Three documents give three different default providers **[fixed]**

- `config.yml:24` sets `provider: google_vertex`, which rejects API keys entirely and needs
  ADC plus project/region.
- `README.md:116-117` says "an LLM provider key (default Anthropic) ... set
  `ANTHROPIC_API_KEY`".
- `.Renviron.example:10` labels Gemini the "default provider".

`byok_effective_config()` (`R/byok.R:100-113`) only overrides the provider when a key is
pasted in the UI, so a user following the README verbatim sets `ANTHROPIC_API_KEY`, gets the
`google_vertex` path, and nothing works.

### 16. Accessibility: the Evidence signals column is invisible to screen readers **[fixed]**

`R/review_render.R:67-79` rendered each signal as a bare `<i>` with an inline height and no
text, `title`, or `aria-label`. A whole column of data, arguably the most information-dense
part of the primary output, announced as nothing.

Also fixed: no `scope="col"` on table headers (`R/review_render.R:211-226`), and
`--faint: #9c8a80` on `--surface: #fffdfb` measured about 2.7:1
(`www/css/genescout.css:18`), below the WCAG AA threshold of 4.5:1. It is used for the "N
sources" context strip text and the "Insufficient" grade pills.

Remaining accessibility gaps, not addressed:

- Colour-only encoding distinguishes annotation from evidence signals
  (`R/review_render.R:75`), with no text or shape alternative.
- Rows are interactive (`tabindex="0"`, click/Enter/Space) but carry no `role="button"`, no
  `aria-selected`, and the table has no `role="grid"`.
- No arrow-key navigation; tabbing is the only keyboard path through a 200-row result.
- No skip-link past the navbar.

## Low severity and hygiene

### 17. Documented error contract does not exist **[fixed in docs]**

`CLAUDE.md:91` and `PLAN.md:45` promise clients raise a typed `genescout_http_error`.
`grep -rn "genescout_http_error"` returns zero hits in code. Clients return
`list(ok = FALSE, ...)` from `R/http.R:292-337`.

The actual contract is applied consistently and is arguably a better design, but it was not
the documented one. Failures are values that must be checked rather than conditions that
cannot be ignored, which is the mechanism behind finding 6.

Two inconsistencies remain within the real contract:

- `graphql_error()` (`R/http.R:165-176`) returns `list(ok = FALSE, error = ...)` with no
  `status` and no `data`, breaking the shape for the seven files that return it verbatim.
  `R/tools/opentargets.R:59` then appends `gene`, producing a fourth distinct shape.
- `europepmc_search()` (`R/tools/literature.R:34-36`) reports a legitimate zero-hit query as
  `ok = FALSE, error = "No literature found."`. The sibling `europepmc_count()` gets this
  right. So a gene with genuinely no papers is indistinguishable from an outage.

### 18. Dead dependencies and undeclared ones **[fixed]**

- `DT` (`DESCRIPTION:21`) and `purrr` (`:27`) are Imports with zero uses in the codebase. The
  ranked table is hand-rolled HTML (`R/review_render.R:203+`).
- `quarto` (`DESCRIPTION:36`) has zero uses and is in neither `renv.lock` nor `manifest.json`.
- `withr` is used 39 times across the suite and was declared nowhere; it resolved only via
  `testthat`'s transitive import.

### 19. Dead code

Zero call sites, not even in tests: `gather_pathway_disease()`, `gather_literature()`,
`gather_variant_effect()` (`R/evidence.R:75-158`), `is_grounded()` (`R/citation_gate.R:25`),
`narrate_candidate()` (`R/agents.R:156`), `specialist_tools` (`R/agents.R:14`).

The three `gather_*` functions transitively make roughly 150 of `R/evidence.R`'s 234 lines
unreachable from the app. `specialist_tools` is notable: the restricted tool allowlist is a
documented part of the architecture (`CLAUDE.md`), but the real specialists read pre-fetched
evidence and register no tools, so it was never wired.

Test-only: `app_version()` (`R/utils.R:1`, which also duplicates and contradicts the
`GENESCOUT_VERSION` read at `R/http.R:31-40`), `safe_read_rds()`, `not_implemented()`,
`as_gene_lists()`, `collect_gene_lists()`, `parse_candidates()`, `flatten_gene_lists()`.

Dead config: `config.yml:30,72,78,84` define a `caveats` model role. `model_for()` is only
ever called with `"orchestrator"`, `"specialist"`, and `"input_curator"`. The caveats stage is
deterministic by design (`R/caveats.R:3-4`), so the role misleads a reader into thinking the
veto is model-driven.

### 20. Rubric drift: two sources of truth

- `GENESCOUT_GRADE_BREAKS` (`R/scoring.R:236`) is hardcoded and absent from `rubric.yml`.
  Changing the High/Moderate cutoff is a code change, contrary to `CLAUDE.md:82`.
- `GENESCOUT_DEFAULT_FLAGS` (`R/caveats.R:24-31`) lists 6 genes; `rubric.yml:78-100` lists 20.
  If `load_rubric()` fails, which `caveat_config()` tolerates at `R/caveats.R:36`, the veto
  silently degrades from 20 genes to 6 with no signal.

Note also that `cross_source` carries the highest weight in the rubric (2.0, `rubric.yml:40`)
while its evidence rows are grounded on `source_id = "user-list:<label>"` with no URL
(`R/enrich.R:1959-1972`). That is a defensible design decision, but the Connectors page
(`R/connectors.R:283-288`) tells the user every connector value "carries a real source id (an
accession or citation)", which is not true of the highest-weighted signal. Worth either
rewording the claim or reconsidering the weight.

### 21. Blocking work on the main thread

R/Shiny is single-threaded per process. Three paths block the event loop:

- `modules/mod_review.R:210-233`: `run_enrich()` inside `withProgress()`. `R/parallel.R` fans
  per-gene work to mirai daemons, but the main session still blocks on the result. The
  progress bar animates while every other session on the process is frozen.
- `modules/mod_input.R:601-623`: `resolve_disease()`, addressed in finding 14.
- `modules/mod_review.R:303-321` and `mod_results.R:246-262`, `:329-350`:
  `genescout_llm_run()` blocks on `m[]` (`R/llm_offload.R:116`). The crash-isolation rationale
  is sound and the comment is honest about the tradeoff, but it is still a synchronous block
  for the duration of an LLM call.

`promises` is already an Import (`DESCRIPTION:26`) and is used in `mod_chat.R:163`, so the
async pattern is understood here. `R/llm_offload.R:116` could return the `mirai` object rather
than `m[]`, since mirai objects work with `promises::then()`.

### 22. Parallel path defeats both the cache and the circuit breaker

`R/http.R:17` creates the cache at source time and `:62` the breaker; `R/parallel.R:130-134`
spins up N daemons and tears them down on every run.

- Each daemon gets its own empty cache, destroyed at teardown. The parent's cache is never
  populated in parallel mode, so the 30-minute cache does almost nothing for exactly the large
  runs it was built for. `clingen_gene_validity()` fetches its bulk CSV once per daemon.
- A dead host costs 3 failures times 6 daemons before all trip, and the state is discarded, so
  the next run pays it again. With `req_retry(max_tries = 3)` at `R/http.R:276`, worst case per
  host per daemon is 3 times 3 times 15s before tripping.

### 23. Performance: quadratic scans in the hot path

None of these matter at 20 genes; all matter at the 300-gene ceiling the code supports via
`GENESCOUT_INTERACTIVE_INPUT_MAX`.

- `R/enrich.R:2173-2189`: `count_present()` runs once per gene and scans all of
  `signals_long` each time, twice over.
- `R/enrich.R:2050-2053`: `conn[conn$symbol == sym, ]` inside the per-gene loop.
- `R/enrich.R:1599`, `:1719`: `order <- c(order, key)` growth inside loops.
- `R/report.R:838-840`: one full-evidence filter per gene.
- `R/tools/clingen.R:96-101`: the HTTP body is cached but the CSV parse is not, so a 300-gene
  run parses the full ClinGen gene-validity CSV 300 times.

### 24. Other client-level issues

- `R/tools/gnomad.R:104-113` requests every variant of a gene and the parsed result is cached
  for 30 minutes in a `cachem::cache_mem()` with the default 1 GB cap (`R/http.R:127`). For
  TTN or MUC16, exactly the FLAGS genes users paste, that is tens of MB per gene held in a
  long-lived Shiny process. Set an explicit `max_size`, or do not cache this endpoint.
- `R/tools/string.R:50-59` puts up to 500 identifiers into a GET query string (about 4 kB),
  which is over the practical limit for many intermediaries. STRING accepts POST for this.
- `R/report.R:701-705` renders external `source_url` values as `<a target="_blank">` with no
  `rel="noopener"`. `R/review_render.R:349-355` and `R/connectors.R:230` both get this right.

### 25. Long functions

| Function | Location | Approx. lines |
| --- | --- | --- |
| `input_server` | `modules/mod_input.R:436` | 349 |
| `results_server` | `modules/mod_results.R:38` | 320 |
| `genescout_signal_registry` | `R/enrich.R:176` | 260 |
| `review_server` | `modules/mod_review.R:128` | 259 |
| `run_enrich` | `R/orchestrate.R:30` | 208 |
| `gs_detail_pane` | `R/review_render.R:287` | 178 |
| `genescout_provenance` | `R/orchestrate.R:395` | 167 |
| `run_specialists` | `R/specialists.R:310` | 145 |
| `apply_caveats` | `R/caveats.R:64` | 133 |

Three are worth splitting on merit rather than length:

- **`run_enrich`** carries at least seven responsibilities: priors loading, disease seeding,
  cross-source derivation, source selection, three near-identical auto-signal append rules,
  resolution, dispatch, gating, assembly. The three append blocks (`:146-175`) are a natural
  table-driven rule list.
- **`genescout_provenance`** is a 34-line literal map plus eight append blocks that re-declare
  metadata already present on each `genescout_signal()`. It should derive from the registry.
  As written, adding a connector requires editing it too, and forgetting to is invisible in
  the audit trail. Note that `CLAUDE.md:100-106`'s four-step "how to add a data source" does
  not mention this function, so it will drift.
- **`apply_caveats`** is one loop with four inlined trigger bodies. Each is independent and
  should be a `function(genes, cfg) -> list(penalty, reasons)` in a list, so adding a trigger
  is additive and each is unit-testable.

### 26. Duplication across the 24 tool clients

The clients are thin, but each hand-rolls the same four blocks.

| Repeated construct | Occurrences |
| --- | --- |
| `list(ok = FALSE, error = ...)` literals | 137 across 24 files |
| blank-input guard | 24 |
| post-fetch `!res$ok` guard | 24 |
| `vapply(rows, ... pluck_at ...)` field extractor | 31 |
| `source_id`/`source_url` `paste0` pairs | 22 |

Three abstractions are missing, worth roughly 400 lines together:

1. **A guarded-fetch helper.** Every client is: guard blank input, build query, call
   `http_*_json`, guard `!ok`, call a pure parser. That 10-14 line prelude is repeated 24
   times. A `tool_fetch(guard, request, parser, source)` would collapse it and make the error
   contract enforceable in one place, which is the root of finding 6.
2. **A field extractor.** The `vapply`/`pluck_at` idiom is written out 31 times, with a local
   `field <- function(key)` closure redefined in at least five files.
3. **A grounded-tibble constructor.** Every parser hand-builds `source_id` and `source_url`. A
   `grounded(prefix, id, web_base)` would make the citation-gate contract structural rather
   than conventional.

Within single files: `clinvar_gene_pathogenic_count()` and
`clinvar_gene_disease_pathogenic_count()` are about 90% identical
(`R/tools/clinvar.R:17-52` vs `:72-110`); `opentargets_parse_rows()` and
`opentargets_targets_parse()` are near-twins (`R/tools/opentargets.R:101-140` vs `:182-226`).

**Colliding constants.** All files are `source()`d flat into `globalenv`
(`R/load_components.R:17`), so the last definition wins silently. `GNOMAD_URL` is defined
twice with identical values (`R/tools/gnomad.R:9`, `R/tools/variant_effect.R:11`), so it is
benign today but is a live collision hazard. The same endpoint also appears under two names
in two places: `EUTILS_BASE` (`R/tools/variant_effect.R:13`) vs `CLINVAR_EUTILS_BASE`
(`R/tools/clinvar.R:8`), and `GNOMAD_DATASET` vs `GNOMAD_GENE_DATASET`, both `"gnomad_r4"`.
There is no namespacing, so any future collision is also silent.

### 27. Path resolution bypasses `genescout_app_path()`

`genescout_app_path()` (`R/config.R:18-21`) exists so a hosted service with an uncontrolled
CWD works. `load_byok_models`, `load_rubric`, `list_contexts`/`load_context`, and the version
read all use it. Two do not:

- `load_config()` (`R/config.R:24`), `path = "config.yml"`.
- `read_prompt()` (`R/utils.R:27`), `file.path("prompts", ...)`.

Both are called inside mirai daemons, which set `GENESCOUT_APP_ROOT` (`R/parallel.R:143`,
`R/llm_offload.R:49`) but never `setwd()`, and in the plumber service. It works today only
because local daemons inherit the parent's CWD, which is the exact assumption
`genescout_app_path()` was written to remove.

### 28. Hardcoded provider default in five engine sites

`CLAUDE.md` says not to hardcode a provider string. `config$provider %||% "anthropic"` appears
at `R/agents.R:31`, `R/curate.R:363`, `R/specialists.R:252`, `R/input_agent.R:400`, and
`R/orchestrate.R:564`.

Five copies of a default that contradicts the shipped config (`config.yml:24` is
`google_vertex`). A missing or renamed `provider:` key silently routes the whole pipeline to
Anthropic. `load_config()` should validate that `provider` is present, or one place should own
the default. The three further copies in `modules/mod_keys.R` are more defensible as UI code.

### 29. Provenance over-reports discovery sources

`R/orchestrate.R:405-410` sets `seeded_sources` unconditionally when disease mode is on. But
`seed_disease_genes()` wraps each of the three in `tryCatch` (`R/enrich.R:1514-1560`) and
skips any that fails or returns zero rows. A run where PanelApp returns 500 still reports
Genomics England PanelApp in the audit trail. Record what actually succeeded, via
`context$seed_data` names.

### 30. `run_review()` and `run_review_request()` drop the disease signals

`R/orchestrate.R:284` and `:343` both default to `registry = genescout_signal_registry()`,
that is `disease_mode = FALSE`, then set `context$disease` and seed the disease universe. So
the CLI and API entry points seed PanelApp and DISEASES genes but never score those signals,
while provenance claims both were queried.

Every real caller works around this by hand (`modules/mod_review.R:165`, `api/plumber.R:121`,
`evals/run_evals.R:49`, `evals/run_benchmark.R:34`, `dev/run_review.R:197`): four independent
copies of the same three-line branch, while the engine's own one-shot entry point gets it
wrong. `run_enrich()` already knows `context$disease` at `:61` and should select the registry
itself.

### 31. `auto_active()` is a constant

`R/orchestrate.R:143-145`. `has_gene_source` is `length(registry) > 0` (`:134`), and
`:130-132` already errored if an explicit selection left the registry empty. So the function
is always TRUE and its first two clauses are unreachable. A user who deselects `cross_source`
or `string` cannot turn them off. The comment at `:136-142` argues this is deliberate; if so
the function should be `function(key) TRUE` with that comment, not three clauses that read
like real gating.

### 32. `guess_type()` misclassifies real gene symbols

`R/parse_input.R:10` uses an unanchored `grepl("[:.]|>|del|ins|dup", x, ignore.case = TRUE)`.
`INS`, `INSR`, `INSIG1`, `INSIG2`, `INSL3`, `INSM1`, and `DELE1` are approved HGNC symbols
that contain `ins` or `del` and are therefore typed `"variant"` with `gene = NA`
(`:28-29`).

Currently latent: `collect_candidate_set()` reads only `tbl$candidate` and ignores `type`
(`:436-459`), and `parse_candidates()` is test-only. But the `type` column of an uploaded
table is silently discarded, and this is a live landmine if that ever changes.

### 33. `max_genes` truncation is arbitrary and mislabeled

`R/orchestrate.R:106-112` truncates after the disease seed is unioned in (`:66-76`), so the
cut is by input order rather than seed strength, unlike the priority-ordered
`cap_seed_symbols` (`R/enrich.R:1447-1475`). The provenance message at `:533-536` says "ranked
the first %d of %d submitted candidate genes", but the count includes engine-seeded genes the
user never submitted.

### 34. Stale comments

- `R/parallel.R:28` claimed a throttle that did not exist (fixed).
- `R/http.R:31` calls itself the single source of truth for the version, contradicted by
  `R/utils.R:1`.
- `R/tools/literature.R:7` says PubTator "is a planned addition"; `R/tools/pubtator.R` shipped.
- `R/tools/opentargets.R:4` still says "Phase 0 vertical-slice client".
- `R/agents.R:1-10` says "nothing here runs until that stage lands", but `R/specialists.R` and
  `R/curate.R` shipped and call `build_chat()` from this file.

### 35. Startup-frozen source picker

`userInterface/page_review.R:3` leads to `source_picker_ui()` (`modules/mod_input.R:222-271`),
evaluated once at app source time. `signal_available(s)` reads env vars at that moment, so
"needs API key" labels and default-checked state are frozen for the process lifetime.
Currently benign, since all key-gated sources are stubs, but it means a future key-gated
source can never be unlocked by a session-pasted key.

### 36. "Use this key" performs no validation

`modules/mod_keys.R:140-165` builds a credential from whatever string was pasted and reports
"Connected: Anthropic." With a typo'd key the user sees a green success message and discovers
the failure minutes later when curation fails. A cheap round-trip, or at minimum a key-format
check, would close the gap.

### 37. Documentation accuracy

| Location | Issue |
| --- | --- |
| `README.md:132` | Says re-run `dev/init-renv.R` to regenerate the lock. `dev/init-renv.R:10` is `if (!file.exists("renv.lock"))`, so with a lock present it prints a message and does nothing. |
| `dev/init-renv.R:13` | Claims to mirror DESCRIPTION Imports/Suggests. It omits `cachem`, `promises`, `rlang`, `mirai`, `quarto`, `thematic`, `plumber` and adds `httptest2`, which is not in DESCRIPTION at all. |
| `README.md:69-73` | "~8 public sources" reads as the total; there are 24 clients and about 17 in the provenance map. |
| `README.md:102-106` | Lists opt-in connectors but omits IMPC, HPA, DGIdb, and Pharos, all of which `CHANGELOG.md:38-40` includes. |
| `README.md:203`, `docs/project_structure.md:32` | Both list only three files in `docs/`; there are six. |
| `docs/project_structure.md:26` | Says `context/` holds `nf1.yaml`; it also holds `lynch.yaml`. |
| `docs/project_structure.md:37-40` | Describes the LLM specialist path as the main flow. The default pipeline is deterministic (`run_enrich` then `rank_result`) with specialists as an opt-in post-step. This inverts the architecture the README gets right. |
| `docs/data_sources.md` | Access dates are all 2026-07-09 to 2026-07-12, and the reproducibility checkbox at `:57` is unchecked. `disease_resolver.R` is a distinct endpoint folded into the Open Targets row. |

### 38. Evals

- `evals/baseline.json` has `generated_at: 2026-07-12`, but `R/enrich.R` last changed
  2026-07-14 (`b6df528`) and `rubric.yml` and `R/scoring.R` on 2026-07-13. The committed
  baseline predates the last engine change.
- `evals/run_evals.R` only *writes* the baseline under `--write-baseline`. Nothing compares
  against it, so the drift detection its own docstring advertises at `:13-17` is not
  implemented; it is a manual `git diff` at best.
- `evals/run_benchmark.R` is advertised at `README.md:179` but is run by no workflow and has
  no test.
- `run_evals.R:19` is `source("global.R")` with relative paths, so it must run from the repo
  root. Running it from inside `evals/` fails with an unhelpful error.

### 39. CI gaps

`.github/workflows/`: `ci.yaml` (format, test, markdown), `secret-scan.yaml`, `pr-title.yaml`,
`evals.yaml`.

- **CI does not use `renv.lock`.** `ci.yaml:37-41` uses `setup-r-dependencies@v2`, resolving
  from `DESCRIPTION` against latest RSPM. CI never tests the pinned environment the Dockerfile
  and `README.md:126-131` promise. A CRAN upgrade can break production while CI stays green.
- No coverage, no `lintr`, no `dependabot.yml`, no CodeQL.
- No matrix. `DESCRIPTION:15` claims R >= 4.3; `renv.lock` pins 4.6.1; neither is verified.
- No `concurrency:` block, so three pushes to a PR run three full CI jobs.
- No `timeout-minutes` on any job, most acute for `evals.yaml`, which hits live APIs.
- `ci.yaml:10-13` fires only on `main`, so a PR targeting any other branch gets no gate.
  `secret-scan.yaml` correctly has no branch filter; the inconsistency looks unintentional.
- `permissions: read-all` (`ci.yaml:17`, `evals.yaml:24`) is broader than the `contents: read`
  actually needed.
- **Four third-party actions are on mutable tags**: `amannn/action-semantic-pull-request@v5`
  (`pr-title.yaml:17`), `gitleaks/gitleaks-action@v2`, `DavidAnson/markdownlint-cli2-action@v20`,
  `posit-dev/setup-air@v1`. The first sits behind `pull_request_target` and receives
  `GITHUB_TOKEN` in its env, so a tag hijack yields a read-scoped token from every fork PR.
  Pin these to commit SHAs. For a repo that runs gitleaks on every push and lists "no secrets"
  as a non-negotiable, unpinned supply-chain-sensitive actions are inconsistent.

Not an issue: the `pull_request_target` usage is otherwise the recommended-safe shape (no
`actions/checkout`, `permissions: pull-requests: read`), and no secrets are exposed to fork
PRs.

`.pre-commit-config.yaml` is solid, with two notes: the `exclude` at `:8` skips `docs/` and
`data/` for **all** hooks including `gitleaks` and `detect-private-key`, which is backwards
from the intent of non-negotiable #5; and the hooks are not mirrored in CI, so a contributor
who skips `prek install` gets no `codespell` or `check-yaml`.

`evals.yaml` is correctly gated (`workflow_dispatch` only, with a documented rationale) and
genuinely needs no API keys, since `run_evals.R` exercises the deterministic spine only.

### 40. Deployment bundle ships tests

`manifest.json` includes 97 test files. `.rscignore` excludes `.Renviron`, `secrets/`, and
`renv/library`, but not `tests/`, `dev/`, or `evals/`. `.dockerignore:16` does exclude them,
so the two deployment manifests disagree about what constitutes the app.

## Appendix: overlap with sibling projects

Reported for context. No extraction is proposed here.

### `bio-engine` is a scoping document, not code

`/Users/samuelbharti/work/projects/bio-engine` contains two files: a 13-line README and a
263-line `docs/shared-package-scoping.md`. There is no R package, no plumber API, no MCP
server, so there is nothing for GeneScout to depend on today.

That document already scopes this problem, recommends *against* a monolithic `bio-engine`
package (it would couple Bioconductor, ellmer, and duckdb into every caller), and proposes
separate repos instead: `biohttp` feeding `bioclients`, plus `shinykit`, `variantkit`,
`reviewerkit`, `kgcore`, `connectivitykit`.

Two points worth knowing: it **names `genescout/R/tools/` as the reference layout** for the
future `bioclients`, so GeneScout is the donor rather than the consumer; and its validation
pilot migrates `variant-reviewer` first, not GeneScout. The proven model in the family is
`biobouncer`, the one real installable package (`pkg-r/`, `pkg-py/`, a `shared/` spec,
published to r-universe).

### Client duplication is real and diverging

| Source | Implementations across the family |
| --- | --- |
| Open Targets | 6 |
| Ensembl/VEP | 5 |
| ClinVar | 5 |
| MyGene | 5 |
| UniProt | 5 |
| gnomAD | 4 |
| GTEx, STRING, PanelApp, DGIdb, Pharos, disease resolver | 2 each |

Spread across `genescout`, `variant-reviewer`, `multi-variant-reviewer`, `gene-list-builder`,
and `biobouncer`. The function surfaces barely overlap; three different return contracts
exist. Europe PMC, PubTator, cBioPortal, CIViC, HPA, IMPC, PDBe, QuickGO, ClinGen, and HPO are
unique to GeneScout.

The HTTP substrate has an admitted lineage: `variant-reviewer/R/api_http.R` to
`genescout/R/http.R` ("Adapted from the sibling variant-reviewer app") to
`multi-variant-reviewer/R/http.R`, plus an independent fourth in `knowledge-graph-viewer`. All
four reimplement a per-host circuit breaker. `R/load_components.R` is byte-identical across
five repos; GeneScout's copy has already drifted.

### Patterns worth adopting later

- **`multi-variant-reviewer/tests/testthat/test-egress-gate.R`** parses the real call graph to
  compute the transitive closure of callers of the transport primitives, then asserts no
  module body may call anything in that set. For an app with 24 sources and LLM egress, this
  is the highest-leverage safety test available, and GeneScout has no equivalent.
- **`multi-variant-reviewer/R/status.R`**, a 7-state status envelope, and **`R/progress.R`**,
  a source-to-user-phrasing lookup that is pure and unit-testable. Both directly address
  finding 6.
- **`gene-list-builder/R/source_schema.R`**, a hard canonical `GENE_TABLE_COLS` with
  `as_gene_table()` coercion, so every adapter returns an identical shape.
- A `shinytest2` smoke test, which six siblings have and this repo does not.
- `.lintr` configs tuned for Shiny apps exist in three siblings and are copyable verbatim.

### Where GeneScout leads

GeneScout is the most advanced LLM app in the family and the only one with an eval harness
(`evals/`, `rubric.yml`, `.github/workflows/evals.yaml`), externalized prompts (`prompts/`),
a citation gate, mirai crash isolation for LLM calls, or a plumber API surface. Its
`_brand.yml` is the richest and its accessibility is the strongest. Cost/token tracking and
LLM response caching are absent family-wide, so there is nothing to copy there; both remain
open opportunities.

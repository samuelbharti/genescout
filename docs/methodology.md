# GeneScout methodology: how it works and why you can trust it

This is the consolidated, human-readable account of what GeneScout does to a gene
list and why each output can be traced back to a source. It is written for a
researcher deciding whether to trust a ranking, and for a reviewer of the eventual
methods paper. It complements, and does not replace:

- [`prompts/scoring-rubric.md`](../prompts/scoring-rubric.md): the exact scoring &
  caveats rubric (the reviewable spine of the ranking).
- [`docs/data_sources.md`](data_sources.md): every data source with endpoint,
  version/release, and access date (reproducibility).
- [`README.md`](../README.md): the product overview and quickstart.

> **Research use only.** GeneScout is a hypothesis-prioritization aid. It produces
> **research evidence**, never a clinical call: no diagnosis, no treatment advice,
> and no ACMG/AMP pathogenicity classification. ClinVar and gnomAD are read as
> research evidence, not as clinical determinations.

---

## 1. The one idea

A candidate list (genes, and, by design, variants or perturbation hits) plus a
disease/phenotype context goes in; a **plausibility-ranked, fully-cited review**
comes out. The ranking is **deterministic and reproducible**: no language model
touches the score. Two optional LLM stages (a curator and specialist agents) sit
*on top* of the ranking and only ever read, filter, and summarize evidence the
deterministic pipeline already retrieved and cited. They never rank and never
introduce a fact. So the number you sort on is defensible on its own, and the AI is
an accelerator, not the source of truth.

## 2. The pipeline

```text
candidate list + optional disease/tissue context
        │
        ▼  parse            normalize input into a candidate_set (multi-source, tagged)
        ▼  resolve          MyGene batch: symbol/alias/id → canonical Ensembl id (dedupe)
        ▼  (discovery)      with a disease: seed candidate genes from OT/PanelApp/DISEASES
        ▼  enrich           per gene, pull one signal from each selected public source
        ▼  citation gate    drop any evidence row lacking a source_id (grounding)
        ▼  rank             weighted composite of normalized per-signal values
        ▼  caveats / veto   deterministic anti-bias override (down-rank or veto)
        ▼  grade            High / Moderate / Low / Insufficient (+ Vetoed)
        │
        ├─ report           auditable HTML + CSV (scores · evidence · caveats · next steps)
        ├─ (optional) curate with AI   compaction to a target list size, grounded
        └─ (optional) specialists      per-gene synthesis over the gene's own evidence
```

The engine is split so the UI stays responsive: `run_enrich()` does the expensive
network half once per run; `rank_result()` is a pure function that recomputes the
composite, caveats, ranking and grade from the cached evidence, so moving a weight
slider **re-ranks instantly without re-querying** (see
[`R/orchestrate.R`](../R/orchestrate.R)).

## 3. Grounding: no ungrounded claims, enforced structurally

Grounding is GeneScout's first non-negotiable, and it is enforced by construction, not
by trust:

- **Every signal is a real record.** Each per-source client (`R/tools/*.R`) returns
  a typed value plus a `source_id`: a database accession or a citation id (an Open
  Targets association id, a ClinVar VCV, a PMID, a STRING edge, …). A client that
  cannot ground a value returns a miss, never a guess.
- **The citation gate drops the ungrounded.**
  [`R/citation_gate.R`](../R/citation_gate.R)`::validate_evidence()` inspects every
  evidence row before it is accepted; any row without a `source_id` is rejected and
  recorded in `rejected` (visible, not silently dropped). Because evidence flows
  through a schema that *requires* `source_id`, grounding is a structural property.
- **The LLM stages inherit the gate.** A specialist or the curator returns a
  structured object whose citations are filtered against that gene's real evidence
  ids; a fabricated PMID or accession is removed before it can be shown. A gene the
  model never saw cannot be introduced, because it can only choose from the ranked
  candidates.

Net effect: gene names, effect sizes, and paper references in the output come from
tool calls, never from a model's memory.

## 4. Scoring: a transparent composite

Full detail is in [`prompts/scoring-rubric.md`](../prompts/scoring-rubric.md); the
essentials:

- Each source contributes one **signal**, normalized to a comparable 0-1 scale, with
  a **role**: an *evidence* signal (functional consequence, disease association,
  literature support, cross-source corroboration, …) counts toward the score;
  an *annotation* signal (within-list network connectivity, tissue relevance) only
  *nudges* a gene and never penalizes an isolated one. An isolated candidate may
  simply be novel.
- The **composite** is a weighted mean over the *evidence* signals (a missing
  evidence signal counts as 0 but still divides, so **breadth is rewarded** and a
  broadly-supported gene beats a narrow-but-famous one); *present* annotations are
  then folded in and only ever nudge a gene up. Weights live in
  [`rubric.yml`](../rubric.yml) and are surfaced in the in-app legend and the live
  weight sliders. Rank is by composite.
- The **grade** is a badge on the composite: **High** (≥ 0.5), **Moderate** (≥ 0.2),
  **Low** (< 0.2), **Insufficient** (no gradable signal). *Insufficient is a valid,
  first-class outcome: the engine never inflates a grade to avoid it.*
- **Discovery mode** (a disease context is given) makes scoring **disease-specific**:
  association to *that* disease, ClinVar scoped to it, gene+disease co-mention, plus a
  seeded candidate universe (PanelApp/DISEASES). The same engine generalizes across
  contexts because the priors are a config file ([`context/*.yaml`](../context/)),
  not code. NF1 and Lynch syndrome ship as references.

## 5. Caveats & veto: the anti-familiar-gene-bias mechanism

This is the paper's novelty hook and a first-class stage, not a footnote. A
candidate that looks compelling on raw prominence but is suspect gets **down-ranked
with a stated reason**, or **vetoed** (forced to the bottom, grade `Vetoed`):

- **FLAGS / recurrent-artifact genes** (e.g. TTN, MUC16, OBSCN): *veto*.
- **Common in gnomAD** (population-frequent pLoF): *caveat*.
- **Single weak source**: *caveat*.
- **Unrelated-tissue-only** expression: *caveat*.

Every caveat records *why* it fired, on the candidate itself. The whole stage is
deterministic ([`R/caveats.R`](../R/caveats.R)) and reproducible, with no LLM in the
ranking path. The **caveats benchmark** ([`evals/run_benchmark.R`](../evals/run_benchmark.R))
quantifies the contribution: each case is enriched once, then ranked twice (with
and without caveats), and the demonstrable effect is that TTN, which grades **High**
among the NF1 drivers in the no-caveats baseline, is sunk to **Vetoed, last**. If the
stage ever stops changing outcomes, the benchmark fails.

## 6. Evaluation: the trust spine

The eval set ([`evals/test_cases.yaml`](../evals/test_cases.yaml),
[`evals/run_evals.R`](../evals/run_evals.R)) hits live APIs, so it runs **on demand**
(`Rscript evals/run_evals.R`) and via a manual-dispatch GitHub workflow, never as a
per-PR gate. Each case asserts three invariants:

1. **Identity**: every candidate resolves to the gene it *named*. This exists
   because a real regression once resolved the symbol **TTN to a different gene,
   TTR** (a fuzzy alias match out-scored the exact symbol), and the grade/order
   assertions passed anyway. The ranking "held" while the identity was wrong. The
   guard ([`R/eval_checks.R`](../R/eval_checks.R)) now asserts every candidate
   round-trips to its own symbol, and optional `expect_identity` anchors pin exact
   Ensembl ids. Its logic is covered offline
   ([`tests/testthat/test-eval-checks.R`](../tests/testthat/test-eval-checks.R)) on a
   synthetic TTN→TTR mis-resolution, so the protection lives in CI even though the
   live eval does not.
2. **Grade**: the known drivers grade High (NF1 in the NF1 context; the MMR drivers
   in Lynch).
3. **Order**: the negative-control passenger (TTN) ranks strictly last.

A committed **baseline** ([`evals/baseline.json`](../evals/baseline.json), regenerated
with `--write-baseline`) records what the pipeline produced on a given date (each
candidate's resolved id, rank, grade, and composite), so a future run can be diffed
for drift. Because live databases grow, grades and ranks may legitimately move; the
baseline is a snapshot, and the invariant assertions above are the pass/fail gate
(identity is exact).

## 7. Reproducibility & provenance

- **Pinned environment.** [`renv.lock`](../renv.lock) pins R and every package; the
  Docker build uses the same lock, so a clone reproduces the tested environment.
- **Recorded sources.** Every data source is logged in
  [`docs/data_sources.md`](data_sources.md) with endpoint and access date; adding or
  changing a source requires updating it. Each run also computes a **provenance**
  list of exactly which sources it queried (`genescout_provenance()`), including audited
  truncations (seed cap, input cap, STRING cap); nothing is silently limited.
- **Deterministic core.** The ranking has no randomness and no model; the same input
  over the same source state yields the same ranking.
- **HTTP hygiene.** All clients go through one wrapper ([`R/http.R`](../R/http.R))
  with timeout, bounded retry, a success-only cache, a per-host circuit breaker, and
  a contact-bearing user agent.

## 8. The optional AI stages (accelerators, not authority)

Both are optional, grounded, and off the ranking path. See the in-app **AI Agents**
page for the full walkthrough.

- **Curate with AI**: one model call compacts the ranked shortlist to a target list
  size, with an include/exclude + one-line rationale + cited ids per gene. It can only
  pick from the ranked genes; citations are filtered to real evidence; with no LLM it
  falls back to the top genes by rank.
- **Specialist agents**: three domain specialists (variant · pathway/disease ·
  literature) each read *only* their domains' grounded evidence for a top candidate,
  then an orchestrator synthesizes one per-gene verdict (an integrated read, a
  research-plausibility level (compelling / plausible / uncertain / weak), key
  caveats, and one priority next experiment). They fetch nothing new; a finding whose
  citation is not in the gene's evidence is dropped.

Crash-safety: these calls run in a background process, so stopping or refreshing
mid-call cannot take down the R session.

## 9. Limits (stated plainly)

- Signals are as current as the live databases; a source outage blanks its column for
  that run (the run survives, the gap is visible).
- Grades are relative research-prioritization signals, not probabilities and not
  clinical determinations.
- Network connectivity and tissue relevance are cohort-/context-relative annotations,
  so their contribution depends on the rest of the list and the named tissues.
- Variant/rsID-level review is built at the client layer but not yet wired into a
  user-facing mode; the current path is gene-level.

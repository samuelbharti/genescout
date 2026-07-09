# CANDID

**C**andidate **A**nnotation a**N**d **D**isease-informed **I**nterpretation of evi**D**ence

An agentic evidence-review workbench for research genomics. CANDID takes a
candidate list — variants, genes, or perturbation hits — plus a biological
context (e.g. *NF1*-associated cancer), and turns it into a **plausibility-ranked
research review**: what each candidate is, what evidence supports it, what is
uncertain, and what experiment or analysis should come next.

> **Research use only.** CANDID is a hypothesis-prioritization aid for
> researchers. It is **not** a clinical decision-support tool and does not
> provide diagnosis, treatment guidance, or ACMG/AMP variant classification.

---

## The problem

After sequencing, differential expression, or a perturbation screen, you end up
with a long list of candidates. The next step is still painfully manual: you move
between VCFs, annotation tables, pathway databases, PubMed, prior papers, and your
own notes to decide which candidates are worth following up. It is slow, hard to
reproduce, and biased toward genes you already know.

CANDID compresses that loop. Give it a candidate table and a disease context, and
it returns a transparent, cited, ranked review you can act on — with the
uncertainty made explicit instead of hidden.

## What makes it different

- **Candidate-agnostic input.** Variants, gene symbols, or perturbation hits — the
  same pipeline handles all three.
- **Evidence is grounded, not guessed.** Every claim traces to a database record or
  a citation. Unsupported statements are blocked before they reach the report.
- **A caveats stage that can veto a score.** A candidate that looks compelling but is
  common in the population, supported only by unrelated-tissue evidence, or backed
  by a single weak paper gets flagged and down-ranked. This is the
  anti-familiar-gene-bias mechanism, and it is a first-class stage, not a footnote.
- **Auditable output.** The report is a reviewable artifact: per-candidate scores, the
  evidence behind each score, the caveats, and suggested next experiments.
- **Context-driven, not NF1-locked.** The disease context is a config file; NF1 ships
  as the reference example, but any context can be dropped in.
- **Provider-agnostic.** Orchestration runs on [ellmer](https://ellmer.tidyverse.org/),
  so the LLM provider (Anthropic Claude by default, or OpenAI, Gemini, Bedrock, …) is
  a config change, not a code change.

## How it works

CANDID is an R Shiny app with an [ellmer](https://ellmer.tidyverse.org/)-based
agent engine. An orchestrator parses the input, then fans out to three specialist
agents that run in **isolated, parallel contexts** (`parallel_chat_structured()`)
— each queries public biological databases through thin [httr2](https://httr2.r-lib.org/)
clients and returns only distilled, structured evidence. A citation gate rejects any
evidence item without a source id; a caveats stage then scores and, where warranted,
vetoes candidates before the report is assembled.

```text
candidate list + context
          │
   ┌──────▼───────┐
   │ Orchestrator │  (ellmer)
   └──────┬───────┘
   ┌───────┼────────────────────────┐
   ▼       ▼                        ▼
Variant   Pathway &            Literature
effect    disease
VEP       Open Targets         Europe PMC
gnomAD    Reactome / PAGER     PubTator
ClinVar
   └───────┼────────────────────────┘
          ▼
   Citation gate  →  Scoring + caveats/veto
          ▼
   Evidence-ranked report  (scores · citations · next steps)
```

## Data sources

All sources are public and require no API key unless noted. Versions and access
dates are tracked in [`docs/data_sources.md`](docs/data_sources.md) for reproducibility.

| Stage | Source | Used for |
| --- | --- | --- |
| Parse / resolve | MyGene | Symbol → Ensembl / Entrez / UniProt |
| Variant effect | Ensembl VEP | Functional consequence |
| Variant effect | gnomAD | Population frequency (rarity) |
| Variant effect | ClinVar (NCBI E-utilities) | Known significance (evidence, not diagnosis) |
| Pathway & disease | Open Targets Platform | Gene–disease associations |
| Pathway & disease | Reactome | Pathway membership |
| Pathway & disease | PAGER | Pathway / gene-set enrichment |
| Literature | Europe PMC | Citation retrieval |
| Literature | PubTator | Pre-annotated gene/disease/variant mentions |

## Quickstart

### Requirements

- R ≥ 4.3
- An LLM provider key for your configured provider (default Anthropic):
  copy `.Renviron.example` to `.Renviron` and set `ANTHROPIC_API_KEY`.

### Install

```bash
git clone https://github.com/samuelbharti/candid.git
cd candid
# First-time setup: install dependencies and write renv.lock.
Rscript dev/init-renv.R
# On later clones, once renv.lock is committed:
Rscript -e 'renv::restore()'
```

### Launch the app

```r
shiny::runApp()
```

### Run the pipeline headless

```bash
Rscript dev/run_review.R \
  --input data/examples/nf1_candidates.tsv \
  --context nf1 \
  --out report.html
```

## Repository layout

See [`docs/project_structure.md`](docs/project_structure.md) for the full map.

```text
candid/
├── global.R / ui.R / server.R  # app entry (bslib template)
├── config.yml                  # provider/model per role
├── R/                          # engine + utilities (+ R/tools/ bio-DB clients)
├── modules/ · userInterface/   # Shiny modules + page layouts
├── prompts/ · context/         # agent prompts + disease-context priors
├── data/examples/              # public/synthetic example candidates
├── dev/run_review.R            # headless CLI
├── evals/ · tests/             # ranking benchmark + unit tests
└── docs/                       # data_sources, described_plan, project_structure
```

## Roadmap

See [`PLAN.md`](PLAN.md) for the full phased plan. Near-term:

- [x] Thin vertical slice: candidate list → one source → summary → report
- [x] Multi-source deterministic enrichment + weighted-mean ranking (live sliders)
- [x] Dual-mode discovery: seed genes from a disease, disease-aware scoring
- [x] Scoring rubric + caveats/veto stage (deterministic: FLAGS veto, weak-source)
- [x] AI curator: grounded, model-agnostic final compaction
- [x] Shiny UI with per-candidate evidence cards
- [x] Eval harness on known NF1 biology
- [ ] Three parallel specialist agents with real data tools
- [ ] Preprint + evaluation write-up

## Citation

If you use CANDID, please cite it via [`CITATION.cff`](CITATION.cff). A preprint
describing the method and evaluation is planned.

## License

[MIT](LICENSE). Built for *Built with Claude: Life Sciences* (2026).

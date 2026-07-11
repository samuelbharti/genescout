# Data sources

Provenance for every external source CANDID queries. Keep this current: when you
add or change a source, record its endpoint, version/release, access date, and terms.
This table is what a reviewer will ask for and what makes the method reproducible.

> Fill in version/release and access date as you wire each client. `TBD` = not yet
> integrated or not yet recorded.

| Source | Stage | Endpoint | Version / release | Access date | Terms allow programmatic use | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| MyGene | resolve / dedupe | <https://mygene.info/v3> | v3 | 2026-07-09 | Yes | Symbol → Ensembl / Entrez / UniProt (canonical dedupe key) |
| Open Targets Platform | ranking signal + discovery | <https://api.platform.opentargets.org/api/v4/graphql> | v4 (GraphQL) | 2026-07-09 | Yes | Enrichment: max gene–disease association (0–1). Discovery: disease→associated targets (seed genes + disease-specific score); disease name→EFO/MONDO resolution + DOID cross-reference |
| Genomics England PanelApp | discovery signal | <https://panelapp.genomicsengland.co.uk/api/v1> | REST v1 | 2026-07-09 | Yes | Discovery mode: green/amber diagnostic-panel genes for a disease (confidence 1.0 / 0.5) |
| DISEASES (Jensen Lab) | discovery signal | <https://api.jensenlab.org> | Knowledge + Textmining channels | 2026-07-09 | Yes | Discovery mode: disease→gene associations by DOID (confidence 0–5, max across channels) |
| Europe PMC | ranking signal | <https://www.ebi.ac.uk/europepmc/webservices/rest> | REST v6.9 | 2026-07-09 | Yes | Gene mention count (`hitCount`); in discovery mode, gene∧disease co-mention count |
| ClinVar (NCBI E-utilities) | ranking signal | <https://eutils.ncbi.nlm.nih.gov> | E-utilities JSON (esearch) | 2026-07-09 | Yes | Count of pathogenic / likely-pathogenic variants per gene (disease-scoped in discovery mode). Evidence only; not clinical classification |
| DGIdb | ranking signal | <https://dgidb.org/api/graphql> | v5 (GraphQL) | 2026-07-09 | Yes | Count of curated drug–gene interactions (druggability, evidence) |
| Pharos / IDG | ranking signal | <https://pharos-api.ncats.io/graphql> | Pharos (GraphQL) | 2026-07-09 | Yes | Target Development Level (Tclin/Tchem/Tbio/Tdark) → 0–1 druggability score (annotation) |
| Ensembl VEP | variant mode (dormant) | <https://rest.ensembl.org> | REST (GRCh38) | 2026-07-09 | Yes | Functional consequence (by rsID); reserved for a future variant mode, not in the gene-list ranking |
| gnomAD | ranking signal | <https://gnomad.broadinstitute.org/api> | gnomad_r4 (GraphQL) | 2026-07-09 | Yes | LOEUF loss-of-function constraint (annotation, lower is better). Variant-level allele frequency reserved for a future variant mode |
| PubTator3 | ranking signal | <https://www.ncbi.nlm.nih.gov/research/pubtator3-api> | v3 API (search) | 2026-07-10 | Yes | Count of articles PubTator3 has tagged with a gene ENTITY (`search/?text=@GENE_<entrez\|symbol>`, top-level `count`). Entity-precise successor to the Europe PMC symbol count (evidence). Prefers the resolved NCBI Gene id so aliases disambiguate; a real 0 is a genuine zero |
| Reactome | ranking signal | <https://reactome.org/ContentService> | Release 97 (ContentService) | 2026-07-09 | Yes | Per-gene pathway membership via HGNC mapping. Signal = count of the gene's disease-associated pathways (`isInDisease`) + pathways matching a context pathway prior (annotation, nudges up only). Each pathway is grounded evidence (Reactome stable id) |
| GTEx | ranking signal | <https://gtexportal.org/api/v2> | v2 API (GTEx v8) | 2026-07-10 | Yes | Per-gene median expression across tissues (2 GETs: gene→gencodeId, then medianGeneExpression). Signal = tissue relevance = peak median TPM in a study *tissue of interest* / peak across all tissues (0–1, annotation). Only active when tissue(s) of interest are supplied AND at least one maps to a GTEx tissue; also feeds the *unrelated-tissue-only* caveat. Each matched tissue is grounded evidence (gencode id) |
| STRING | ranking signal | <https://string-db.org/api> | v12 (`json/network` + `json/get_string_ids`) | 2026-07-10 | Yes | Within-list interaction connectivity: one `json/network` call over the resolved candidate set (`required_score=700`, i.e. combined score ≥0.7); per gene, the count of OTHER candidates it interacts with (degree). A `get_string_ids` call reconciles STRING's preferredName back to the queried HGNC symbol so a renamed gene (e.g. SEPTIN9→SEPT9) is credited, not dropped. Annotation, and COHORT-RELATIVE (the one signal whose value depends on the rest of the list), so it only nudges a connected gene up, never penalizes an isolate. Appended only for a multi-gene list (≥5 input tokens); a genuinely queried isolate scores a grounded degree 0 while a failed/un-queried gene reads NA. The query is capped at 500 genes, and any overflow is audited in the provenance. Each edge is grounded evidence (`STRING:<a>-<b>`) |
| Human Phenotype Ontology (HPO) | ranking signal (opt-in) | <https://ontology.jax.org/api> | Jax ontology API | 2026-07-10 | Yes | `network/annotation/NCBIGene:<entrez>` → the Mendelian/phenotype diseases HPO associates with the gene. Signal = count of associated diseases MATCHING the study disease context (by MONDO/name), else all associated diseases (evidence, opt-in). Each disease is grounded evidence (OMIM/ORPHA id) |
| Human Protein Atlas (HPA) | ranking signal (opt-in) | <https://www.proteinatlas.org> | `<ensembl>.json` | 2026-07-10 | Yes | Per-gene `<ensembl>.json` → curated `Protein class` + `Disease involvement`. Signal = count of distinct disease/cancer classifications (e.g. "Cancer-related genes", "Tumor suppressor") (annotation, opt-in, cancer axis). Grounded by the HPA gene page. (Tissue/subcellular/cancer-prognostic fields reserved for later signals) |
| Cross-source corroboration | ranking signal | (user input; no network) | n/a | n/a | n/a | Multi-source runs only: count of the user's OWN input sources a gene appears in (evidence; breadth beats a single loud source, capped below High). Grounded in the user's provenance (`user-list:<label>`), not an external claim; the disease-discovery seed source is excluded |
| cBioPortal | ranking signal (opt-in) | <https://www.cbioportal.org/api> | REST (`mutation-data-counts/fetch`) | 2026-07-10 | Yes | Cross-cancer somatic mutation frequency (cancer axis). One POST over a fixed large public cohort (MSK-IMPACT, ~10,945 tumors), keyed by HUGO symbol; signal = mutated distinct samples / all profiled samples (0–1). Research evidence (recurrence), not a clinical call. `source_id = cbioportal:msk_impact_2017` |
| CIViC | ranking signal (opt-in) | <https://civicdb.org/api/graphql> | GraphQL (`gene(entrezSymbol:)`) | 2026-07-10 | Yes (CC0) | Curated clinical evidence weight (cancer axis). One GraphQL POST keyed by HUGO symbol; signal = `Gene.stats.evidenceItemCount` (count of expert-curated evidence items). Research evidence (curated literature), not a clinical call. Grounded by the CIViC gene link (`CIViC:gene:<id>`) |
| ClinGen | ranking signal (opt-in) | <https://search.clinicalgenome.org/kb/gene-validity/download> | Bulk gene-validity CSV (CC0) | 2026-07-10 | Yes (CC0) | Gene–disease validity strength (gene-disease axis). No per-gene JSON API, so the public bulk CSV is fetched once (cached) and filtered by HUGO symbol; signal = strongest established classification (Definitive 4 / Strong 3 / Moderate 2 / Limited 1), scoped to the study disease by MONDO id (separator-normalized) or disease-name word. Each curation is grounded evidence (assertion report URL) |
| UniProt (Swiss-Prot) | ranking signal (opt-in) | <https://rest.uniprot.org/uniprotkb> | REST (`<acc>.json`, field `cc_disease`) | 2026-07-11 | Yes | Curated gene–disease involvement (gene-disease axis). One GET keyed by the resolved Swiss-Prot accession; signal = count of curated `DISEASE` comments, scoped to the study disease by name token when one is given, else all. Independent expert-review channel corroborating HPO / ClinGen / DISEASES. Each disease is grounded evidence (UniProt disease id `DI-…`, with its OMIM/MIM cross-reference). `causal` flags "caused by variants" (Mendelian) vs "may be involved" |
| QuickGO / Gene Ontology | ranking signal (opt-in) | <https://www.ebi.ac.uk/QuickGO/services> | `annotation/search` REST | 2026-07-11 | Yes | Molecular-function annotation (function axis). One GET keyed by the resolved UniProt accession (`aspect=biological_process`, `includeFields=goName`); signal = count of distinct biological-process GO terms whose name matches a study pathway prior (e.g. RAS/MAPK for NF1), else the count of distinct BP terms. Annotation (nudges up, never gates). Each term is grounded evidence (GO stable id + QuickGO term page) |
| PDBe | ranking signal (opt-in) | <https://www.ebi.ac.uk/pdbe/api> | `mappings/best_structures` (SIFTS) | 2026-07-11 | Yes | Experimental 3D-structure coverage (structure/tractability axis). One GET keyed by the resolved UniProt accession; the SIFTS mapping lists one row per chain, collapsed to distinct PDB entries; signal = count of distinct experimental structures (a structurally characterized target is more tractable for mechanistic follow-up; complements Pharos). Annotation (nudges up, never gates). Each structure is grounded evidence (PDB id + PDBe entry page) |

## Source selection

Sources form a **catalog** (`candid_source_catalog()`); each run activates a
**selected subset**, gated at query time — a deselected source is never called (a
weight of 0 only mutes its ranking contribution, still paying the network cost).
The active set resolves by precedence: an explicit selection (the review-request
`options$sources`, the Shiny picker, or `dev/run_review.R --sources`) **>** a deploy
default (`config.yml` `sources:`) **>** each source's built-in `default_on`. A
key-gated source with no key present is dropped silently, so a keyless deploy runs
the keyless subset. The active set is recorded in the run provenance.

Key-gated databases (OncoKB, COSMIC Cancer Gene Census, DisGeNET, OMIM, DrugBank)
are registered in the catalog as **stubs** — metadata only, `default_on = FALSE`,
and unavailable without their key — so a front end can show "needs an API key"
without a live client yet. The HTTP layer supports header/bearer auth
(`http_get_json(..., headers = source_auth_headers(sig))`), with the token redacted
from logs and excluded from the cache key; their live clients land in a later round.

## Reproducibility checklist

- [ ] Every integrated source has a real version/release and access date above.
- [ ] Each client sends a descriptive `User-Agent` and respects rate limits.
- [ ] Dependency versions are pinned (`renv.lock` / `DESCRIPTION`).
- [ ] A container recipe reproduces the environment.
- [ ] Example candidates in `data/examples/` are public or synthetic only.

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
| STRING | ranking signal | <https://string-db.org/api> | v12 (`json/network`) | 2026-07-10 | Yes | Within-list interaction connectivity: one `json/network` call over the resolved candidate set (`required_score=700`, i.e. combined score ≥0.7); per gene, the count of OTHER candidates it interacts with (degree). Annotation, and COHORT-RELATIVE (the one signal whose value depends on the rest of the list), so it only nudges a connected gene up, never penalizes an isolate. Appended only for a multi-gene list (≥5 input tokens). Each edge is grounded evidence (`STRING:<a>-<b>`) |
| Cross-source corroboration | ranking signal | (user input; no network) | n/a | n/a | n/a | Multi-source runs only: count of the user's OWN input sources a gene appears in (evidence; breadth beats a single loud source, capped below High). Grounded in the user's provenance (`user-list:<label>`), not an external claim; the disease-discovery seed source is excluded |

## Reproducibility checklist

- [ ] Every integrated source has a real version/release and access date above.
- [ ] Each client sends a descriptive `User-Agent` and respects rate limits.
- [ ] Dependency versions are pinned (`renv.lock` / `DESCRIPTION`).
- [ ] A container recipe reproduces the environment.
- [ ] Example candidates in `data/examples/` are public or synthetic only.

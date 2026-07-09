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
| PubTator | ranking signal (planned) | <https://www.ncbi.nlm.nih.gov/research/pubtator3-api> | TBD | TBD | Yes | Gene-tagged literature count; precise successor to the Europe PMC symbol count |
| Reactome | ranking signal (planned) | <https://reactome.org/ContentService> | TBD | TBD | Yes | Pathway membership |
| PAGER | ranking signal (planned) | TBD | TBD | TBD | TBD | Pathway / gene-set enrichment |
| STRING | ranking signal (planned) | <https://string-db.org/api> | TBD | TBD | Yes | Within-list interaction connectivity |

## Reproducibility checklist

- [ ] Every integrated source has a real version/release and access date above.
- [ ] Each client sends a descriptive `User-Agent` and respects rate limits.
- [ ] Dependency versions are pinned (`renv.lock` / `DESCRIPTION`).
- [ ] A container recipe reproduces the environment.
- [ ] Example candidates in `data/examples/` are public or synthetic only.
